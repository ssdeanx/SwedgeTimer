# class_matrix_2026-10-19 — READ-ONLY feature-matrix audit (6 classes × 12 systems)

Desk: class-matrix. No addon files touched. Single NEW bench file per
`bench/briefs/brief_class-matrix_2026-10-19.md` (confirmed absent at lane start).
Date: 2026-10-19. Tree read as-is; harness baseline taken from
`desks/journal.md:8` (37 steps, 0 failed; luacheck 2/0) — no test runs in-lane
(read-only brief).

Extends, never re-derives: `bench/feature_hunter_audit_2026-10-19.md`
(H1–H6/M1–M7), `bench/feature_proctor_audit_2026-10-19.md` (G1–G6),
`bench/rogue_readiness_2026-10-19.md` (§§1–4 + residuals),
`bench/rogue_erroraudit_2026-10-19.md` (F1–F8, ADEQUATE),
`bench/rogue_deep_2026-10-19.md` (§4 handoff), `bench/lessons.md`.

Evidence bar: every file:line anchor below was read on current disk 2026-10-19.
Labels: proven offline (read) vs UNCONFIRMED (needs a live client).
Per-cell verdicts: WIRED / MISSING / DEGRADED + severity (casual vs top-100
ms stakes) + owning lane for the fix (code / options / tests / docs).
Cells tagged (P) touch files owned by parallel writer lanes
(five-class-gaps on the five class files; rogue-parity/diag/docs/auditfixes on
rogue files + shared panels) — graded as-read, reconciled in §13, not in the
verdict.

Cell counts: 72 cells — 68 WIRED, 0 MISSING, 4 DEGRADED.
No MISSING cell: every class wires every shared system at least structurally.

## 1. HUD slots + get_hud_state (frozen contract hud.lua:20-60)

| Class | Verdict | Evidence |
|---|---|---|
| DRUID | WIRED | `classes/druid.lua:1703` HUD_SLOTS, `:1887` provider (P) |
| HUNTER | WIRED | `classes/hunter.lua:1142` HUD_SLOTS, `:1256` provider (P) |
| PALADIN | WIRED | `classes/paladin.lua:2797` HUD_SLOTS, `:2964` provider (P) |
| SHAMAN | WIRED | `classes/shaman.lua:2426` HUD_SLOTS, `:2533` provider (P) |
| WARRIOR | WIRED | `classes/warrior.lua:2458-2491` family slot sets, `:2633` provider (P) |
| ROGUE | WIRED (P) | `classes/rogue.lua:706` HUD_SLOTS (8 slots), `:770` provider; single-table reuse pinned `tests/rogue_state.lua:688-692` |

Note: warrior is the only class with family-varying slot sets (Era rend vs
later HS); all six providers follow the optional-field contract (nil = not
reported). No gap.

## 2. Guide provider + gather_guide_inputs (contract nextaction_ui.lua:13-82)

| Class | Verdict | Evidence |
|---|---|---|
| DRUID | WIRED | `classes/druid.lua:1651` guide, `:1495` gather (P) |
| HUNTER | WIRED | `classes/hunter.lua:1093` guide, `:793` gather (P) |
| PALADIN | WIRED | `classes/paladin.lua:2671` guide, `:2465` gather (P) |
| SHAMAN | WIRED | `classes/shaman.lua:2384` guide, `:2265` gather (P) |
| WARRIOR | WIRED | `classes/warrior.lua:2385` guide, `:2167` gather (P) |
| ROGUE | WIRED (P) | `classes/rogue.lua:512` guide, `:580` gather; `inputs_unknown` ownership `:690-693` (M6 pattern), lust latch `:688-689` (M5 pattern) |

All six guides expose slots + gather + evaluate per the frozen shape; all six
gathers write into a caller-owned reused table (no per-tick allocation).
Rogue gather sets no `inputs.G`/swing speed — the rogue engine is an
energy-tick model, not a swing-speed model; no rule in `rogue_guide.lua`
reads G. UNCONFIRMED whether any future rogue rule needs a GCD echo;
left as a follow-up question for the rogue engine owner (code), not a gap.

## 3. get_rotation_key (contract rotationtext.lua:18-24)

| Class | Verdict | Evidence |
|---|---|---|
| DRUID | WIRED | `classes/druid.lua:1993`; suite pins `tests/rotationtext_state.lua:600-617` (P) |
| HUNTER | WIRED | `classes/hunter.lua:1337`; pins `:558-574` (P) |
| PALADIN | WIRED | `rotationtext.lua:222` — documented deviation: lives in rotationtext.lua, not `classes/paladin.lua` (header `:219-224` says the move is a pure cut-and-paste); pins `:237-296` |
| SHAMAN | WIRED | `classes/shaman.lua:2616`; pins `:623-637` (P) |
| WARRIOR | WIRED | `classes/warrior.lua:2733`; pins `:580-594` (P) |
| ROGUE | WIRED (P) | `classes/rogue.lua:1270` (hunter shape, rogue-parity lane); pins `tests/rogue_state.lua:1249-1308` + `tests/rotationtext_state.lua:640-678` |

All six classes implement the provider; `RT.provider` (`rotationtext.lua:189-195`)
resolves by `player_class` key. No gap. The paladin location deviation is
pre-existing and documented — do not "fix" without moving the pins.

## 4. on_bar_update driving guide + HUD in order

| Class | Verdict | Evidence |
|---|---|---|
| DRUID | WIRED | `classes/druid.lua:1178`; guide `:1202` then hud `:1211` (P) |
| PALADIN | WIRED | `classes/paladin.lua:1231`; guide `:1261` then hud `:1268` |
| SHAMAN | WIRED | `classes/shaman.lua:1963`; guide `:1994` then hud `:2002` (P) |
| WARRIOR | WIRED | `classes/warrior.lua:1898`; guide `:1922` then hud `:1930` (P) |
| ROGUE | WIRED (P) | `classes/rogue.lua:1173`; guide `:1202` then hud `:1208`; never gated on `st.is_mainline` (`:1174-1176`) |
| HUNTER | DEGRADED | `classes/hunter.lua:384`; hud `:400` runs BEFORE guide `:423` — reversed vs all five siblings (P) |

D1 (HUNTER order): severity CASUAL. Both consumers run every tick; neither
reads the other's output, so no ms-scale consequence exists on current disk.
Top-100: none. Owning lane: code (five-class-gaps follow-up: swap to
guide-then-hud for uniformity, or record the divergence as intended —
one-line change, no suite impact beyond order pins that do not exist).
Call site is guarded (`bars.lua:680-682` H2 fix), so a throw in either
consumer is isolated regardless of order.

## 5. on_combat_exit preserving the mainhand record (G4)

| Class | Verdict | Evidence |
|---|---|---|
| DRUID | WIRED | `classes/druid.lua:257` — clears maul/badge state only (P) |
| HUNTER | WIRED | `classes/hunter.lua:467` — clears queued shots only (P) |
| PALADIN | WIRED | `classes/paladin.lua:1549` — clears twist/glow state only |
| SHAMAN | WIRED | `classes/shaman.lua:869` — clears in-flight weave cast only (P) |
| WARRIOR | WIRED | `classes/warrior.lua:539` — clears queued/rage/proc state only (P) |
| ROGUE | WIRED (P) | `classes/rogue.lua:1217` — explicitly documents the G4 rule: never touches the mainhand record |

Dispatch `main.lua:1010-1018` fires the hook once per exit; no class module
writes `self.mainhand`/`self.offhand`/`self.ranged` in its exit path (verified
by reading all six bodies). G4 holds tree-wide. No gap.

## 6. Spell-id tables (highest-rank-wins + Anniversary name-fallback where CLEU matched)

| Class | Verdict | Evidence |
|---|---|---|
| DRUID | WIRED | `resolve_rank` `:61`, maul `:164`/`:1424`, mangle `:1428`, TF/berserk `:1723-1727`; name fallback `:399-401`, `:538`, `:586` (P) |
| HUNTER | WIRED | `get_family_spell_id` `:676-700`, `resolve_known` `:724-762`, rank-1 fallback `:621`; SoD/Wrath sets `:121-144` (P) |
| PALADIN | WIRED | seal tables `:67-100`, exorcism `:141`, jotc `:1647`; R1 name fallback `resolve_soc_proc_names` `:566-578` + `twist.lua:67-88` |
| SHAMAN | WIRED | `WEAVE_*_IDS` tables `:33-205` with name fallbacks at every consumer (`:452-499`, `:1259-1279`) (P) |
| WARRIOR | WIRED | `resolve_rank` `:220`, hs/cleave `:261-266`/`:2093-2097`, battle shout `:72`, name fallback `:616-627` (P) |
| ROGUE | DEGRADED (P) | `ST.ROGUE.SPELL_IDS/POISON_IDS` EMPTY `:116-117` by design (no remembered ids — lessons rule); lust ids hardcoded `:104`; apply_spell_ids retry `:167-170` |

D2 (ROGUE empty tables): severity LOW, CASUAL-today. By-design state per
readiness §1 (ship empty, fill in-client); HUD slots grey-missing rather than
guess (H4-safe — erroraudit P4). Becomes top-100-relevant only once poison/Shiv
CLEU matching lands (needs R1 id+name tables + M3 counter at that time).
Owning lane: code (rogue follow-up, in-client fill). UNCONFIRMED: every id the
fill will claim. NOT a regression: nothing reads the empty tables as success.

## 7. Practice scenarios (practice.lua registry)

| Class | Verdict | Evidence |
|---|---|---|
| DRUID | WIRED | 1 scenario `practice.lua:2366` |
| HUNTER | WIRED | 1 scenario `practice.lua:2096` |
| PALADIN | WIRED | 2 scenarios `practice.lua:1801`, `:1972` |
| SHAMAN | WIRED | 1 scenario `practice.lua:2457` |
| WARRIOR | WIRED | 1 scenario `practice.lua:2217` |
| ROGUE | WIRED (P) | 2 scenarios `practice.lua:2557` (`rogue_energy_pool`), `:2638` (`rogue_ss_window`); NaN-hardened per auditfixes lane |

Registry rejects unknown kinds loudly (`practice.lua:1520-1522`, erroraudit
P3). No class is missing a drill shell; drill quality (grade bands) is pinned
per class in `tests/practice_state.lua` (`:1379-1390` + rogue pins). No gap.

## 8. Diag provider listing (diag.lua PROVIDER_CLASSES)

| Class | Verdict | Evidence |
|---|---|---|
| DRUID | WIRED | `diag.lua:51` member; `guide_state` `:149-178`; summary `:241-242`; pins `tests/diag_state.lua:205` (`:349-353` all six on/off) |
| HUNTER | WIRED | same lines |
| PALADIN | WIRED | same lines + `:128` profile fixture |
| SHAMAN | WIRED | same lines |
| WARRIOR | WIRED | same lines |
| ROGUE | WIRED (P) | same lines + `:133-141` fixtures, `:366-371` absent-degrades-to-none pin (rogue-diag lane) |

All six render `on`/`off`/`none`/`?` per the frozen rule; a missing ROGUE
provider degrades to `none` with count 5/6 (pinned, not silent). No gap.

## 9. Options section (thresholds, copy accuracy, slot toggles, rotation widgets, disabled-gating, order uniqueness)

| Class | Verdict | Evidence |
|---|---|---|
| DRUID | WIRED | `ST.class_opts_funcs.DRUID` `option_tables.lua:3412`; defaults `config_presets.lua:218`; parity pins `tests/options_load_state.lua:526-706` (P) |
| HUNTER | WIRED | section `:3086`; defaults `:309`; same parity pins (P) |
| PALADIN | WIRED | section `:1239`; defaults `:422`; rotation-widget pins `tests/rotationtext_state.lua:334-353` |
| SHAMAN | WIRED | section `:3930`; defaults `:677`; parity pins (P) |
| WARRIOR | WIRED | section `:2595`; defaults `:772`; rampage-toggle pins `tests/options_load_state.lua:651-671` (P) |
| ROGUE | WIRED (P) | section `option_tables.lua:4291`; defaults `config_presets.lua:569-676`; full round-trip pins `tests/options_load_state.lua:1009-1156` (panel↔defaults↔class-key, threshold triple-fallback, colour conversion, cue-absence) |

Panel richness differs by design (PALADIN ~91 threshold/toggle refs for the
twist machine vs 22–35 elsewhere — counted in-lane) — richness follows engine
complexity, not parity. Rotation widgets exist for all six whose module
provides `get_rotation_key` (`option_tables.lua:2441` gate). Disabled-gating:
rogue 10/10 colour rows pinned (erroraudit P4); the shared walker
(`tests/options_load_state.lua:230-259`) enforces numeric orders tree-wide
(1857 widgets / 249 groups per header `:70`). No gap. Shared-file edits belong
to the options lane — this cell is as-read.

## 10. TOC wiring (all 7 flavor TOCs, load order)

All six classes WIRED in all seven TOCs, identical tail order
(druid → hunter → paladin → shaman → warrior → rogue):

- `SwedgeTimer.toc:67-72`, `SwedgeTimer_Vanilla.toc:67-72`,
  `SwedgeTimer_TBC.toc:67-72`, `SwedgeTimer_Wrath.toc:67-72`,
  `SwedgeTimer_Cata.toc:66-71`, `SwedgeTimer_Mists.toc:66-71`,
  `SwedgeTimer_Mainline.toc:66-71` (no `LibClassicSwingTimerAPI` line — kept).
- Root pure guides load before consumers: `SwedgeTimer.toc:44-48`
  (warrior/druid/shaman/hunter/**rogue_guide.lua**), ahead of
  `practice.lua:50` / `main.lua:52` which consume them.
- `tests/toc_check.lua:120-310` pins per-flavor engine divergence both
  directions + class coverage.

No class is missing from any flavor; rogue sits last in the dependency-safe
position (needs config/st.api/frames loaded). No gap. (TOCs are shared with
parallel lanes — as-read; skeleton lane filed done per `desks/journal.md:58`.)

## 11. Test suites (state + contract + options + rotationtext + diag pins)

| Class | Verdict | Evidence |
|---|---|---|
| DRUID | WIRED | `tests/druid_state.lua`, `tests/druid_guide_state.lua`, `tests/druid_energy_state.lua` |
| HUNTER | WIRED | `tests/hunter_state.lua`, `tests/hunter_guide_state.lua`, `tests/hunter_window_state.lua` |
| PALADIN | WIRED | `tests/paladin_state.lua` + `tests/twist_state.lua` + `tests/nextaction_state.lua` (no `paladin_guide_state` — the engine is the shared `nextaction`, not a per-class file; not a gap) |
| SHAMAN | WIRED | `tests/shaman_state.lua`, `tests/shaman_guide_state.lua` |
| WARRIOR | WIRED | `tests/warrior_state.lua`, `tests/warrior_guide_state.lua` |
| ROGUE | DEGRADED (P) | `tests/rogue_state.lua` + `tests/rogue_guide_state.lua` exist and pin provider/HUD/rotation/combat-exit; cross-class pins present (guide_contract `:1256-1344`, rotationtext `:640-678`, options_load §9, diag_state `:366-371`, practice_state `:1390`) |

D3 (ROGUE bars_state/design pins): `tests/bars_state.lua:703` drives five
class keys (PALADIN/WARRIOR/HUNTER/DRUID/SHAMAN) — no ROGUE visual-creation
case, and `tests/design_state.lua` / `tests/designmode_state.lua` carry no
rogue reference (verified by grep). Severity CASUAL (regression-tripwire only;
`tests/rogue_state.lua:565-782` pins provider behaviour, and rogue visuals
`classes/rogue.lua:871-932` follow the sibling setup pattern). Top-100: none
today. Owning lane: tests (add a rogue boot case mirroring the five-class
spec shape `bars_state.lua:834-997`).

## 12. design/designmode integration + LibGlobalCooldown relevance + option_table_presets branch + gcd marker modes

| Class | Verdict | Evidence |
|---|---|---|
| DRUID | WIRED | visuals `classes/druid.lua:1020` (+gcd marker `:760-1058`); presets branch `option_table_presets.lua:1044`; bars_state pins `:982-985` |
| HUNTER | WIRED | `hunter_ui` widget set `classes/hunter.lua:425-426`; presets `:1085`; bars_state `:969-977` |
| PALADIN | WIRED | seal icons/band `classes/paladin.lua:1427+`; presets `:1123`; bars_state `:942-960` |
| SHAMAN | WIRED | weave mirror `classes/shaman.lua:968+`; presets `:1203`; bars_state `:986-997` |
| WARRIOR | WIRED | `setup_warrior_visuals` `classes/warrior.lua:1311`; presets `:1242`; bars_state `:961-968` |
| ROGUE | DEGRADED (P) | visuals exist (`setup_rogue_visuals` `classes/rogue.lua:871`, spark/tint/window/poison `:893-932`); presets branch `:1176` ships; LGC needs no per-class wiring (central `main.lua:47,392-395`); gcd markers are bar-level defaults (`config_presets.lua:161-211`), rogue offhand/ranged ship disabled |

D4 (ROGUE design pin): same root cause as D3 — the visuals exist and follow
the sibling pattern (lockdown-safe retry, cheap per-frame), but no
bars_state/design pin executes them. Same severity (CASUAL), same owning lane
(tests — fold into the D3 case). LGC relevance is uniform: no class wires
LibGlobalCooldown directly; all GCD reads flow through
`get_spell_gcd_duration` / `self.gcd`. The `option_table_presets` per-class
info branches + `gcd_marker_modes` (`:50`, `:695-696`) cover all six classes.

## 13. PROVISIONAL section (parallel-writer ownership — reconcile, don't re-derive)

Graded as-read above; the orchestrator reconciles these against the writer
lanes before acting:

- **Rogue column (all 12 cells, P):** `classes/rogue.lua`, `rogue_guide.lua`,
  rogue blocks in `config_presets.lua` / `option_tables.lua`, rogue pins in
  `tests/rogue_state.lua` / `tests/rotationtext_state.lua` /
  `tests/options_load_state.lua` are owned by rogue-parity (done, get_rotation_key
  + cue-key removal), rogue-diag (done, PROVIDER_CLASSES + pins), rogue-docs,
  rogue-auditfixes (done, F1/F2/F4/F5/F6 pins) per `desks/journal.md:64-77`.
  Any post-read writer edit supersedes the rogue cells above.
- **Five-class class-file details (P):** `classes/{druid,hunter,paladin,shaman,
  warrior}.lua` are owned by the parallel five-class-gaps writer lane
  (`bench/briefs/brief_five-class-gaps_2026-10-19.md` — explicitly forbids
  touching rogue/config/options/compat/TOCs). D1 (hunter order) is filed as a
  follow-up for that lane, not an edit here.
- **Shared files (as-read, writer-adjacent):** `diag.lua:51`,
  `option_tables.lua` sections, all 7 TOC tails, `tests/run.sh` registration.
  No edit proposed here; options/diag/TOC cells above describe the read tree.

## Summary

| Severity | Count | Items |
|---|---|---|
| DEGRADED (fix when convenient) | 4 | D1 hunter guide/HUD order; D2 rogue empty id tables (by design); D3 rogue bars_state gap; D4 rogue design pin (same fix as D3) |
| MISSING | 0 | — |

No cell mistimes a cast, fabricates a confident prompt on unknown data, or
hides a failure: every load-bearing path degrades to nil/unknown/silent with
a pin (inheriting the hunter H4/M4/M6 and errorauditF3–F8 verdicts by pointer,
not re-audit).

### Verdict: ADEQUATE WITH FOUR DEGRADED NOTES

D1 → code (five-class-gaps follow-up). D2 → code (rogue in-client fill wave;
UNCONFIRMED ids stay out until a client confirms them). D3/D4 → tests (one
rogue boot case in bars_state shape). Nothing here blocks the writer lanes or
the owner in-client session; every UNCONFIRMED above is a real in-client
check, not a hedge.

*Limitations: read-only (no suite runs; harness baseline cited, not re-proven).
`compat.lua`/`main.lua`/`bars.lua` interiors cited at the exact lines the
prior audits pinned — not re-read in full. In-client timing, `/dump`
slot-types (R1), live lust/haste windows, and all TESTING.md visuals are out
of scope.*

# rogue+hunter Era/SoD/TBC verification 2026-10-19

Desk: rogue-hunter-eratbc. Scope ONLY: `classes/rogue.lua`, `rogue_guide.lua`,
`classes/hunter.lua`, `hunter_guide.lua`, `hunter_ui.lua`,
`tests/rogue_state.lua`, `tests/rogue_guide_state.lua`, `tests/hunter_state.lua`,
`tests/hunter_guide_state.lua`. Shared files (`hud.lua`, `bars.lua`,
`practice.lua`, `practice_ui.lua`, `designmode.lua`, `design.lua`,
`guide_contract`, `compat.lua`, `main.lua`, option tables/config, diag,
`run.sh`, TOCs, docs, versions) verified READ-ONLY. No git. No invented ids.

Method: drove both pure engines with frozen sim-line inputs for ERA / SOD /
TBC (42-check script, `/tmp/opencode/verify_eratbc.lua`, all green); confirmed
HUD slot resolution paths + provider nil-safety; confirmed practice grading
bands + designer hooks via the frozen suites. Full harness + luacheck
re-verified on the untouched tree.

## 1. Next-action vs sim APL — GREEN (all three families, both classes)

Source rows: `bench/rogue_rotation_audit_2026-10-19.md`,
`bench/hunter_rotation_audit_2026-10-19.md`. Engine suites green:
`rogue_guide_state` 642/0, `hunter_guide_state` 1121/0.

Rogue (all in `rogue_guide.lua`, gathered by `classes/rogue.lua:775-961`):
- ERA: 5CP healthy TTD>8 -> `eviscerate` (E-C1 Evisc-first); SnD missing at
  1CP -> `snd` (F0/H1 ERA 3s/1CP); Tea line 29 (E-G3); sweaty spend >=79
  regardless of tick phase (E-G1); pool band 65/85 (F2 MATCH); Shiv ungated
  (no Mutilate row on ERA); EA refresh 3 (E-G4 MATCH).
- TBC: 5CP healthy -> `rupture` (T-M2 Rupture-first); EA 5s -> `expose`
  (T-G2 imminent 6); EA minimum 15 + wait/release (H6 rule 1a);
  pool single 71 (T-M1 sim-validated); Tea 30 (T-G5); 3CP/TTD6 -> no dump
  (T-C1 5CP/5s floor, no any-CP leak); Shiv withholds on Mutilate-known and
  at/above 5CP (T-G4).
- SOD (ERA + `sod_envenom` latch, `rogue_guide.lua:1145-1152,1254`):
  4CP + stacks -> `envenom` primary outranking rupture (S-C1, exactly
  backwards from Era-base); SnD 4CP/1s (S-G1); Tea 10, 40 while ttd<=15s
  (S-M1); without the latch ERA never envenoms mid-fight (no SoD leak).

Hunter (all in `hunter_guide.lua`, gathered by
`classes/hunter.lua:1173-1462`):
- ERA: aimed_known + clip-safe 3s cast -> `aimed`, shadows multi; multi
  0.5s weave -> `multi`; `steady_known=false` -> silent (no rank-1 fallback);
  inclusive window HOLD; family gates hold (TBC-only rules never fire).
- SOD (ERA + 409433 known): chimera ready -> `chimera` above the weave;
  known-Serpent-down withholds naked Chimera, unknown allows; LnL free
  aimed (clip-gated, ignores CD) above free multi.
- TBC: KC -> `kill_command` #1, then BW, then RF (instant, behind window,
  ahead of weave); multi 0.5s + steady 1.5s filler under clip math;
  `TBC_ARCANE_ENABLED=false` dormant (slot filed — see §5).

## 2. HUD slots — GREEN with two FILED gaps (§5)

- Rogue (`classes/rogue.lua:971-994`, provider `:1048`): all 11 slot names
  (SnD/Rupture/EA/AR/BF/Tea/Kick/Kidney/Vanish/Bandage/Cold Blood) exist on
  vanilla+TBC clients; ids resolve through the client's own GetSpellInfo by
  name at init (`:240-274`), unknown-hides, retry-throttled. Suite
  `rogue_state` 452/0 pins the empty-at-load + resolution + provider shape.
- Hunter (`classes/hunter.lua:1514-1524`, provider `:1628`): rank-1
  fallbacks + name-based rank-agnostic reads (`hud_slot_name`, `:1536`);
  guide icons re-point to current ranks (`resolve_guide_icons`, `:1060`).
  Suite `hunter_state` 597/0 pins Era 3-slot / SoD 4-slot swap / TBC base
  sets + HUD provider. Remaining gaps need out-of-scope files: FILED §5
  (H-HUD-1 Era dead slots, H-HUD-2 TBC Steady 56641 UNCONFIRMED — **the
  56641 question is now settled, see §5**).

## 3. Practice drills — GREEN (S/A/B/C/F + nil)

`tests/practice_state.lua` 1208/0. Rogue `rogue_energy_pool` (S/A/B/C/D/F +
nil, `:1785-1797`) and `rogue_ss_window` (S/A/B/C/D/F + nil, `:1824+`,
swing_known=false -> nil); hunter `hunter_forced_move` (S/A/B/C/F + nil,
`:1606-1612`); shot analytics `summarize_shots` + prepull/weave checklists
(`:1909-2035`). Registry pins (`:1384-1395`) order rogue energy-first.

## 4. Designer preview/integration — GREEN

- Rogue `setup_rogue_visuals` (`classes/rogue.lua:1242`) + per-frame update
  (`:1377`); `tests/design_state.lua:594-602` pins definition + post_init +
  retry wiring.
- Hunter `hunter_ui.init` from `post_init` (`classes/hunter.lua:385-387`) +
  per-frame drive (`:405`); `tests/bars_state.lua:982-983` pins the built
  widget set; range/rapid-fire/aspect/badge widgets all lazy-safe.
- `tests/bars_state.lua` + `tests/designmode_state.lua` +
  `tests/hud_templates_state.lua` green in the 38/0 harness.

## 5. FILED gaps (need out-of-scope files — not built)

- H-HUD-1 (hunter Era HUD dead slots): the guide drops Steady/KC/BW on Era
  (`hunter_guide.lua:27-33`, "dropped rather than shipped dark") but
  `ST.HUNTER.HUD_SLOTS` (`classes/hunter.lua:1514-1524`) always ships all 9
  slots (Steady 56641 / KC 34026 / BW 19574 have no Era existence). The
  provider never errors (nil-safe, GCD-only display), but Era shows three
  dead slots. Repair = family-pick HUD_SLOTS (in-scope part) + census pins
  in `tests/hud_state.lua` (OUT) + options toggles (OUT). FILED.
- H-HUD-2 (hunter TBC Steady name resolution UNCONFIRMED): HUD steady
  `slot.spell` is fixed 56641 (`classes/hunter.lua:1515`) and
  `hud_slot_name` (`:1536-1545`) resolves through it; the guide re-points to
  the live rank via `get_family_spell_id` (`:1061-1064`, TBC 34120) but the
  HUD does not (aimed is the only re-pointed HUD slot, `:1092-1097`). If
  2.5.6 does not know 56641, the Steady slot loses mana/range tints
  (`:1651-1657`) while showing always-ready (harmless for a no-CD spell,
  wrong tints). Needs in-client `GetSpellInfo(56641)` on 2.5.6; fix mirrors
  the aimed re-point. UNCONFIRMED — FILED, not guessed.
  **CORRECTED 2026-10-20 (desk `corpus-corrections`):** the open question is
  **settled** — **56641 is the WotLK Steady Shot rank-1 and does not exist on
  the TBC client at all** (wowhead TBC 56641: no such spell), and the **Forever
  client has no Steady Shot either** (the spell arrived in 2.3). The hunter
  APL build lane re-cut the TBC *rotation* row to **34120** and **removed** the
  Forever row; the guide's own slot fallbacks are the slot's business (filed
  there, not here). Evidence: `bench/hunter_apl_utility_build_2026-10-20.md`
  §3, `bench/hunter_utility_live_2026-10-20.md` §1;
  `bench/rotation_gap_vs_apl_2026-10-20.md` §0.0 **H3**/**H4**. The HUD
  slot's fixed 56641 is left as it is — that is the shipped tree, not a
  bench claim.
- Prior filed rows stand (not re-filed): rogue SnD/AR/BF/Cold Blood
  slot-less icons (`guide_contract` OUT + `nextaction_ui` OUT);
  hunter TBC Arcane dormant (slot + options OUT); Forever Sniper/Hawk ids +
  hawk-count source (CLIENT-UNCONFIRMED); Wrath branches untouched.

## 6. Standing-rule confirmations

- No lust logic added: rogue `update_lust_state` (`classes/rogue.lua:671`)
  is the pre-existing M5 secret-regime canary feeding `inputs_unknown`;
  hunter files contain zero lust reads (H2 CUT holds).
- No Wrath/Forever/SoD-paladin behavior change: zero addon edits this lane;
  Wrath/Forever/RETAIL branches exercised only through the frozen pinned
  paths (suites green, no new pins).
- Shared files untouched: `hud.lua` (`validate_slot` `:232-244` read-only),
  `practice.lua` (registry + grades read-only), `guide_contract` /
  `rotationtext` / `bars_state` / `hud_state` / `design_state` green
  without edits.

## Validation

- `bash tests/run.sh`: **38 steps, 0 failed** (re-verified on the untouched
  tree in-session).
- `luacheck`: **2 warnings / 0 errors** (the floor, both KEEP-ruled).
- `/tmp/opencode/verify_eratbc.lua`: **42 checks, 0 failures** (frozen
  sim-line inputs, ERA/SOD/TBC x rogue/hunter).
- Zero mutations owed (zero touched lines — nothing to prove).

Validation owner: orchestrator. In-client confirmations still owed:
`GetSpellInfo(56641)` on 2.5.6 (H-HUD-2); Era absence of 56641/34026/19574
(H-HUD-1 census); all TESTING.md visuals UNCONFIRMED (owner in-client
session).

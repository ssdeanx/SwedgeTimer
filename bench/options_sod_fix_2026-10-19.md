# Buildout — options-sod-fix (SoD shaman reports: Practice + Design Mode, 2026-10-19)

Scope held exactly: `option_tables.lua` (visibility/routing fix only),
`tests/options_load_state.lua` (pins only). Read-only: `designmode.lua`,
`practice_ui.lua`, `practice.lua`, class files, TOCs, `hud.lua`. No `run.sh`,
TOC, README, CHANGELOG, docs, version edits; no git; no lint-config changes.

## Verdict

1. **No Practice section on shaman: CORRECT, not a bug.** The practice session
   is the paladin twist sim — `practice_ui.init` runs only from
   `ST.PALADIN.post_init` (`classes/paladin.lua:327-328`); no other class calls
   it, and `classes/shaman.lua:3282` documents "No practice branch: Twist
   Practice is paladin-only (no simulation exists for this class)". The
   `shaman_weave` scenario in `practice.lua` is pure math with ZERO
   `practice_ui` consumers (`grep -i shaman|weave practice_ui.lua` = no hits),
   so there is nothing to route a widget to — adding one would be an inert
   toggle (forbidden). Per-class practice options are FILED below (§FILE-S1)
   with consumer + shape; the hunter `hunter_shot_report` →
   `toggle_hunter_report` pair is the shape precedent.
2. **Design Mode page: no in-scope defect renders it empty on SoD.** All four
   checks pass: all 7 flavor TOCs load `design.lua` (line ~50) before
   `designmode.lua` (line ~62); the group builds unconditionally for every
   class (`option_tables.lua:258`, order 1.45; pinned at
   `options_load_state.lua:388`); the dynamic-name `design_toggle` is nil-safe
   with the module absent/live; every design get/disabled is nil-safe on a
   fresh shaman profile (probe: grid on/24, snap on/8, mouse-anchor off).
   The ONE verified throw was the dynamic name on a hollow `st.designmode`
   (table without `is_active`, the partial-load shape) — fixed here with
   callable guards (§Fix). Residual in-client session/render questions that
   need out-of-scope files are FILED (§FILE-S2) with file:line + missing
   evidence.

## Evidence trail (all verified in-lane on the landed tree)

- Practice scoping: `option_tables.lua:2126+` `practice_*` widgets sit inside
  `ST.class_opts_funcs.PALADIN` (starts `:1351`); SHAMAN (`:4388`) carries
  weave/trackers/HUD/rotation/sim-ref/template only — no `practice_*`, no
  `hunter_shot_report`. `practice_ui.init` callers: paladin only
  (`classes/paladin.lua:327-328`; `grep -rn practice_ui.init classes/`
  confirms). `ui.start` without a built panel prints "Practice mode is not
  available." (`practice_ui.lua:2253-2257`) — a shaman Practice button would
  be a dead end, worse than absent.
- Design load/order: `for f in *.toc: design.lua ~50, designmode.lua ~62`
  on all 7 variants (base + Vanilla/TBC/Wrath/Mainline/Cata/Mists).
  `design.lua` file scope is pure (no WoW API; parses clean), so the hollow
  shape is unreachable via TOC/order — but the widget could still throw if
  any future load regression hollows the module, and Ace renders `name()`
  on every page open.
- Probe `/tmp/opencode/probe_design.lua` (shaman + paladin sandboxes, nil /
  hollow / live `st.designmode`): pre-fix, hollow threw at
  `option_tables.lua:280` (`is_active`) and `:288` (`toggle`); post-fix all
  OK, fresh-db reads sane. Hunter `hunter_shot_report` precedent re-read at
  `option_tables.lua:3698-3712` for the FILE-S1 shape.

## Fix

`option_tables.lua` `design_toggle` (was `:276-291`): `name` and `func` now
check `type(st.designmode.is_active) == "function"` /
`type(st.designmode.toggle) == "function"` instead of bare truthiness.
Live consumer unchanged (`designmode.lua:905 is_active`, `:970 toggle`).
No default-visible change: healthy states render/call identically (probe).

## Pins (`tests/options_load_state.lua` §15, "SODOPT")

Shaman: no `practice_toggle`/`practice_weapon_speed`/`practice_reset_position`/
`hunter_shot_report`; Design Mode group present with all 8 widgets + types;
paladin keeps `practice_toggle`; `practice_ui.lua` names no shaman/weave
consumer; `ST.SHAMAN.post_init` builds no session; callable-guard source pins;
name/func behaviour under nil/hollow/inactive/active/stub (incl. route count);
fresh-db default reads. Suite: **1664 checks, 0 failed** (section adds 31 check sites).

## Validation

- `lua5.1 tests/options_load_state.lua` → 1664 checks, 0 failed.
- Full harness `bash tests/run.sh` → **38 steps, 0 failed**.
- Scope luacheck 0/0; repo `luacheck .` → 2 warnings / 0 errors (floor held,
  both pre-existing KEEP-ruled).
- Mutation proofs on `/tmp/opencode/mut_sod/` (tree copy; restored
  byte-identical via `cmp`): M1 (drop `is_active` guard) → 2 FAILs; M2 (bogus
  shaman `practice_toggle`, the wrong "fix") → 1 FAIL (the scoping pin);
  M3 (drop `toggle` guard) → 2 FAILs.

## FILE-S1 — per-class practice options (filed, not built)

When a session-independent practice screen lands for a class, wire ONE
execute widget in that class's section mirroring `hunter_shot_report`
(`option_tables.lua:3698-3712`): `type = "execute"`, order in the class's
7.x practice band, stateful `name()` reading the screen's visibility flag,
`func` nil-safe into the toggle, NO db key (stateless frame toggle — nothing
to default). Consumer contract (to build, out of scope here): a `practice_ui`
screen reading that class's LIVE log/state (never the paladin sim), e.g.
`ui.toggle_weave_report(ST)` rendering `practice.lua` shaman_weave scenario
queries over the `classes/shaman.lua` weave state; hidden by default like the
hunter report. Until the consumer exists, the class correctly shows no
Practice entry. (Note: `bench/settings_audit_2026-10-19.md:126` H-M3 says
"/st practice starts sessions globally" — overstated for non-paladins; on a
shaman it prints "Practice mode is not available.")

## FILE-S2 — Design Mode empty-page residual (filed, not in scope)

Nothing in `option_tables.lua` blanks the page on SoD (group unconditional,
8 valid widgets, all funcs nil-safe post-fix). If the reporter still sees an
empty page in-client, the suspects are all out of scope and need in-client
evidence: (a) AceConfigDialog-on-SoD rendering of the group
(`option_tables.lua:258-371` is the exact tree to inspect with `/st` open);
(b) the Design Mode SESSION overlay set on shaman-SoD — element availability
lives in `designmode.lua:622-738` (bars/hud/rottext/nag register per class,
`practice_panel` gated on `is_active`), toggle path
`main.lua:1743-1747`; (c) whether the player means the options page vs the
session screen — unresolved from the report wording. Missing evidence: a
screenshot or `/st design` chat output from the SoD shaman client.

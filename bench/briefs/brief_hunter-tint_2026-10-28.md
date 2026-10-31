# Brief — hunter-tint (2026-10-28)

Desk: `hunter-tint`. Operator report, verbatim, on the current 2.1.3 tree (TBC
Anniversary, family TBC):

1. "why is mh changing colors for hunter when using ranged."
2. "the only thing the bar does is change color when im using ranged."
3. "ranged and melee are not the samething why are they effecting each other?"
4. "u need to fix it so ranged isnt firing like that unless its actually being used."

Client context: the operator tests on TBC Anniversary and Classic Era; the build must keep
working on every family the TOCs cover. No in-client session is available to this lane —
offline gate only, and say so.

## Write scope (hold it exactly — one writer per file)

- `classes/hunter.lua`
- `hunter_ui.lua`
- `tests/hunter_state.lua`

Do NOT touch: `main.lua`, `bars.lua`, `power_bar.lua`, `config_presets.lua` (owned by the
parallel `bars-decouple` lane), `Libs/`, any TOC, `.luacheckrc`, `tests/run.sh`, `docs/`.

## Verified facts the lane must re-check itself before editing (read, do not assume)

- The only runtime writer of a hunter main-hand fill colour is
  `ST.HUNTER.set_bar_color` — it returns early for every hand except `mainhand`, then
  applies the Raptor Strike tint (shipped ON, `config_presets.lua`, red 207,58,83) or the
  Steady Shot tint (shipped off) when the corresponding queue flag is set.
- Those flags are set in `on_current_spell_cast_changed` from `api.IsCurrentSpell(...)`
  probes, and are cleared in several `on_spellcast_*` paths. A clear path sets the flag
  to false **without repainting the bar**, so the last tint stays on screen until some
  later `set_bar_color("mainhand")` call.
- `on_combat_exit` clears both flags and never repaints.
- The operator's own `/st diag` output (hunter, TBC, this tree) reported
  `swing_mainhand=35/0/29`, `swing_ranged=230/0/190`, `errors none` — the melee wire is
  alive, so this is a colour/state problem, not a missing swing.

## Required outcomes

B1. The main-hand fill must never be recoloured by ranged play. The queue tint may only
    apply while the main-hand hand is actually meleeing — a live main-hand swing cycle —
    and must be cleared the moment that cycle is gone.
B2. Every path that clears a queue flag repaints the main-hand fill immediately, so no
    stale tint survives: the swing that consumes the queued ability, combat exit, target
    change, and the `on_current_spell_cast_changed` clear branch.
B3. The existing Raptor Strike / Steady Shot tint options keep working in melee, with
    their current keys and defaults (do not flip a shipped default in this lane — if you
    believe a default should change, state it as an operator decision in the report).
B4. No new cross-hand coupling: nothing this lane writes may read or write
    `self.ranged`'s cycle, range state, or visibility.

## Rules

- Load and follow the lane skills first: `bench-read`, `desk-open` (desk `hunter-tint`),
  `desk-journal`, and finish with `signal-write`.
- Read every file you edit before editing it.
- No git commands. No lint-config changes. Preserve file line endings.
- `bash tests/run.sh` must stay green (currently 54 steps, 0 failed; luacheck 2 warnings /
  0 errors in 97 files). Re-cut only pins your change genuinely invalidates, and say which.
- Report to `bench/hunter_tint_2026-10-28.md`: what changed (file:line), what was verified
  offline, what remains UNVERIFIED in client, and any operator decision left open.

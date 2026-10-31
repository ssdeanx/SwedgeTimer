---
# Brief — latent-trap-hardening (2026-10-28)

Desk: `latent-trap-hardening`. Follow-up lane dispatched after `widgets-guard` and
`publish-audit` closed on 2026-10-28. Scope is the remaining latent AceDB `'**'`
metatable-trap reads filed by those two lanes, plus the sibling `bar_full_delay` and
`gcd_marker_offset_mode` reads identified in the publish-audit §C.1 sweep.

## The defect

AceDB profiles carry a `'**'` defaults metatable (Libs/AceDB-3.0/AceDB-3.0.lua:88-107)
that CREATES and rawsets a defaults table on any missing-key read. A plain read of an
absent key therefore returns a truthy TABLE, not nil. Reads that rely on nil/absence
silently misbehave: a junk row materialises, a `== nil` fallback never fires, or a
table reaches an API that expects a string/number.

Already fixed in prior lanes: config.lua appearance migration (appearance-fix),
widgets.lua sound_channel (widgets-guard). This lane closes the four remaining filed
instances.

## Write scope (hold it exactly — one writer per file)

- `classes/paladin.lua` — `play_twist_sound` (lines ~1151-1157)
- `main.lua` — `ST:get_class_table` (lines ~233-245) and the `bar_full_delay` read (lines ~1552-1553)
- `option_table_presets.lua` — the `gcd_marker_offset_mode` read inside the `latency_linear_offset` disabled lambda (lines ~127-130)

Do NOT touch: `config.lua`, `widgets.lua` (already fixed), `Libs/`, TOCs, docs, other
classes, `.luacheckrc`, `tests/run.sh`. The broader truthiness reads (form_vis_*, enabled,
require_in_range, dim_oor, etc.) are a DIFFERENT class of defect (nil-defaults / feature
silently off) and are explicitly OUT OF SCOPE — file them, do not fix them.

## Required outcomes

L1. `play_twist_sound` (classes/paladin.lua): read `sound_channel` via `rawget` on the
    class profile row; require `type(channel) == "string"`; fall back to `"Master"` when
    nothing usable is stored; pcall-guard the `PlaySoundFile` call so a bad channel can
    never throw out of the twist playback path. Mutation-proof each branch.

L2. `get_class_table` (main.lua): `return rawget(profile, self.player_class)` so an
    unknown class token never materialises a junk row; preserve the nil return for
    missing/unknown and keep the documented caller contract (bars.lua pcall+type, hud.lua
    `or {}`, practice_ui.lua). No behaviour change for the six shipped classes.

L3. `bar_full_delay` (main.lua): `local bar_full_delay = rawget(db_shared, "bar_full_delay")`
    when db_shared is a table, else nil; nil → 0.5 default. Must not create a defaults
    table on the profile root.

L4. `gcd_marker_offset_mode` (option_table_presets.lua): read via
    `rawget(db, "gcd_marker_offset_mode")` in the disabled lambda so a missing key returns
    nil (widget disabled) without materialising a row. Equality comparisons stay
    `== "Fixed"` / `== "Calibrated"`.

L5. Sweep the three files for OTHER plain reads of possibly-missing AceDB keys that rely
    on a plain read for a decision or API argument (the same `'**'` trap) and fix any
    siblings inside scope; list anything outside scope in the report as follow-ups (with
    file:line). Do not touch the truthiness-default reads (form_vis_*, enabled, etc.).

L6. Tests: identify the suite(s) covering these paths (search tests/ for play_twist_sound,
    get_class_table, bar_full_delay, gcd_marker_offset_mode) and add/adjust pins proving
    the trap is closed against a `**`-shaped profile where applicable. List every pin
    re-cut and why. Mutation proofs on /tmp copies.

## Rules

- Load and follow the lane skills first: `bench-read`, `desk-open` (desk
  `latent-trap-hardening`), `desk-journal`, finish with `signal-write`.
- Read every file you edit before editing it.
- No git. No lint-config changes. Preserve line endings. Version stays **2.1.3**.
- `bash tests/run.sh` must stay green (54 steps, 0 failed; luacheck 2 warnings / 0 errors
  in 97 files). If red only in another lane's pins, say so and do not fix them.
- Report to `bench/latent_trap_hardening_2026-10-28.md`; journal at
  `desks/latent-trap-hardening/`.
- State what still needs a live client (PlaySoundFile return arity/channel names; the
  twist playback path on a real paladin profile).

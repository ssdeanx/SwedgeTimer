# Brief: lazy swing bars (2026-10-21) — no frames unless the bar is in use

**Operator order, 2026-10-21:** *"also make sure bars like oh do not load unless user is
using it."* Clarified by the operator in the same exchange:
- **Scope: the swing bars only** — mainhand, off-hand, ranged. Class UI frames (hunter
  cast/range helper/pet badges, HUD, next-action guide, rotation text, practice panel) keep
  building exactly as they do now; do not touch them.
- **Rule: enabled AND in use.** No off-hand frames without an off-hand weapon, no ranged
  frames without a ranged weapon, and no frames for a bar switched off in the options.
  When the condition first becomes true (weapon equipped, or the option switched on), the
  bar is built then — once, idempotently.

## Today's behaviour (the defect)

`init_timers` (main.lua:742-770) calls `ST:init_visuals_template(hand)` and
`ST:set_bar_texts(hand)` for EVERY hand in `iter_hands()`, for every class, regardless of
weapon or option state. `HUNTER = {"mainhand","offhand","ranged"}` (main.lua:95), so a
two-handed hunter gets a full off-hand frame tree (anchor, hiding anchor, bar, visuals,
textures, markers, deadzone, texts) that can never be used. Visibility is gated separately
(`bar_is_enabled`, main.lua:1923-1936: mainhand always, others `db.enabled` + `has_weapon`)
— the frames themselves are never gated.

## Required

### B1. One idempotent constructor: `ST:ensure_bar(hand)`
- Returns the built state (or the frames); builds only when the hand's gate is true and
  does nothing on a second call (no duplicate frames, no duplicate anchors).
- The gate is exactly: `db.enabled` AND (`hand == "mainhand"` OR `self[hand].has_weapon`).
  `mainhand.has_weapon` is permanently true (main.lua:486) but mainhand is still gated on
  `db.enabled` — the operator's rule is enabled AND in use for all three bars.
- It owns everything `init_visuals_template` + the per-hand `set_bar_texts` /
  `set_gcd_marker_positions` / `set_deadzone_width` initialisation need, so a bar built
  later is identical to one built at load.

### B2. Build points
- `init_timers`: replace the unconditional `init_visuals_template` + `set_bar_texts` per
  hand with `ensure_bar(hand)`; skip the rest of the per-hand init for a hand that is not
  built (the timer data containers `ST[hand]` stay — they are data, not frames; the swing
  engine still records the hand's speed/ends_at).
- Weapon changes (`check_weapons` / the `UnitAttackSpeed` probe path, main.lua:785-812):
  after `has_weapon` is updated, call `ensure_bar(hand)` for the hands whose state flipped
  true. Crossing `speed_offhand == 0` -> non-zero is the equip case; the ranged hand is
  symmetric.
- Option changes: when `db.enabled` is switched on for a hand (option_tables.lua's toggle
  path / the AceConfig setter), call `ensure_bar(hand)`. Do not build on switch-off.

### B3. No teardown
Once built, a bar is never destroyed. Unequipping or switching the bar off hides it
(existing `handle_bar_visibility` / `bar_is_enabled` paths). Rationale: frame destruction
after the fact risks dangling references from the class modules and the design-mode
registry; a session that used the bar has already paid for it. Document this rule in the
function comment.

### B4. Every getter and consumer must survive "not built"
The frames are looked up through `get_anchor_frame`, `get_hiding_anchor_frame`,
`get_visuals_frame`, `get_bar_frame` (bars.lua:419-434). Grep every caller and make each
one nil-safe:
- bars.lua internals: `configure_*`, `on_bar_active/inactive`, `set_bar_texts`,
  `needs_range_string`, `set_deadzone_width`, `set_bar_color`, `set_gcd_marker_positions`,
  `update_zones`, `onupdate_common`, `show_bar`/`hide_bar`, `handle_bar_visibility`,
  `on_attack_speed_change`, `on_latency_update`, `on_gcd_length_change`.
- Class modules that read a bar frame (shaman `oh_bar:IsShown()` already has an `and`
  guard; warrior reads `has_weapon`) — FILE anything that would nil-index, do not rewrite
  class logic.
- A hand that has no frames must behave exactly like a disabled bar: no show, no update,
  no text, no error. `iter_hands()` still iterates it — decide and document whether a
  built-state check short-circuits the per-hand work (preferred: one early return in each
  per-hand function, one `bar_is_built(hand)` predicate, so the code reads the same).

### B5. Do NOT change
- `bar_is_enabled`'s contract (mainhand always true when enabled) — visibility semantics
  stay; only frame creation becomes lazy.
- The swing engine, timer data, GCD markers' duration math, ranges, class hooks, the
  engine-dead fallback. The practice panel and every class UI are out of scope.
- No default changes: `ST.bar_defaults.enabled = true` stays.

## Proof required (offline, mutation-proofed)

NEW suite `tests/lazy-bars_state.lua`, a WoW sandbox that COUNTS frame creations (a stub
`CreateFrame` registers every frame it returns, per name/parent):
1. off-hand hand with `has_weapon = false`, bar enabled -> the off-hand frame set is NEVER
   created (count zero); the mainhand set is created; `set_bar_texts`/`onupdate_common`
   for the off-hand hand run without error and without touching a frame.
2. off-hand with `has_weapon = true`, bar enabled -> created once.
3. bar disabled in options for a hand that has a weapon -> not created; switching the
   option on at runtime -> created then, exactly once (second call adds nothing).
4. equipping an off-hand at runtime (has_weapon flips) -> created then, once; a second
   weapon-changed event adds nothing.
5. mainhand disabled -> mainhand frames not created at init; mainhand enabled -> created.
6. ranged hand for a non-ranged class/hand with no ranged weapon -> not created; with one
   -> created.
7. Unbuilt hand: `handle_bar_visibility`, `on_bar_active`, `on_bar_inactive`,
   `on_attack_speed_change`, `set_gcd_marker_positions`, `update_zones` all run clean.
8. The built-state predicate and `ensure_bar` are idempotent (frame count unchanged on
   repeat calls).

Then:
- Find and update every existing suite that pins frame counts / per-hand frame existence
  (`grep -rn "init_visuals_template\|get_bar_frame\|get_visuals_frame\|CreateFrame" tests/`,
  plus any `bars_state` / `main_init_state` count pins).
- `bash tests/run.sh` green with exact numbers; `luacheck` at the standing floor
  (2 warnings / 0 errors).
- MUTATION PROOFS on a `/tmp/opencode` copy only: for each new guard (the ensure gate, the
  idempotence, the nil-safe getter, the runtime-enable path, the runtime-equip path),
  remove it and the owning suite must FAIL with quoted output.
- FILE the `tests/run.sh` line — the orchestrator adds it.

## Scope / write permission
- YOU OWN: `bars.lua`, `main.lua`, `option_tables.lua` (only the per-hand enabled setter,
  if that is where the toggle lands), the NEW `tests/lazy-bars_state.lua`, and the existing
  suites that pin the old always-build behaviour.
- YOU MUST NOT edit: `compat.lua`, `hunter_ui.lua`, `Libs/**`, `classes/**` (FILE class
  issues with file:line), `tests/run.sh`, `CHANGELOG.md`, `README.md`.
- **DISPATCH NOTE:** `main.lua` is currently owned by the running `range-engine-tbc` lane
  (exact-yard range state + class `post_init` guard). This lane must be dispatched only
  after that lane lands and the orchestrator has reconciled it — the brief assumes the
  post-range-engine main.lua. Re-read the range/`post_init` regions before editing.
- **Context discipline:** `bars.lua` and `main.lua` are large. Targeted greps and small
  `sed -n` reads only; never read a file end to end.
- No git. No lint-config changes. Warnings traced (wire-not-strip), never silenced with
  `_`. `bars.lua` and `main.lua` are CRLF — preserve. No new protected/secure calls.

## Mechanics (skills — CALL these tools, in order)
`bench-read` (desk journal + `bench/lessons.md` + the bench, journals before artifacts) ->
`desk-open desks/lazy-bars/` -> `desk-journal` -> `signal-write`.

## Deliverable
`bench/lazy_bars_2026-10-21.md` (confirm absent first): the gate rule as implemented, every
build point, the never-destroy decision, the nil-safety list, exact suite numbers, the
mutation list, the filed run.sh line, and every UNCONFIRMED item (in-client: a two-handed
hunter must show NO off-hand bar; equipping an off-hand must make it appear without a
reload; switching a bar off must leave no frames).

## Validation owner
The orchestrator (re-runs the harness, re-reads the diff, hands the operator the copy list
and the in-client checklist).

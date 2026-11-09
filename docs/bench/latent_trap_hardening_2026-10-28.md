# latent-trap-hardening report (2026-10-28)

Desk: `latent-trap-hardening`. Scope: AceDB `'**'` metatable trap reads in
`classes/paladin.lua`, `main.lua`, `option_table_presets.lua`. Version unchanged at 2.1.3.

## Diff shape

### L1 — `classes/paladin.lua` `play_twist_sound`
- Sound key coerced to string before `twist_sounds[...]` lookup; a non-string
  (the metatable's junk table) falls back to `fallback_key` instead of
  indexing with a table.
- `sound_channel` read via `rawget(db, "sound_channel")`; `type(channel) ~= "string"`
  falls back to `"Master"`.
- `PlaySoundFile(path, channel)` wrapped in `pcall(PlaySoundFile, path, channel)`.

### L2 — `main.lua` `ST:get_class_table`
- `return rawget(profile, self.player_class)` (was `profile[self.player_class]`).
- Unknown/missing class token keeps the documented nil answer; no junk class
  row is materialised on the profile.

### L3 — `main.lua` `bar_full_delay` read (in `SWING_TIMER_STOP`)
- `bar_full_delay` is `rawget(db_shared, "bar_full_delay")` only when
  `db_shared` is a table, else nil; nil → `0.5` default. No defaults table
  is created on the profile root.

### L4 — `option_table_presets.lua` `latency_linear_offset` disabled lambda
- `mode = rawget(db, "gcd_marker_offset_mode")` (guarded on `type(db) == "table"`).
- Equality comparisons remain `mode == "Fixed"` / `mode == "Calibrated"`.

### L5 — in-scope siblings fixed
- `main.lua` `class_activation` read → `rawget(class_db, "class_activation")`.
- `main.lua` `set_adjusted_latencies`: `latency_scale_factor` / `latency_linear_offset`
  via `rawget` with shipped defaults (1.0 / 0.0).
- `main.lua` `get_gcd_marker_time_offset_seconds`: `gcd_marker_offset_mode` and
  `latency_linear_offset` via `rawget`.
- `classes/paladin.lua` `play_twist_sound` sound key coercion (above).
- `classes/paladin.lua` `get_twist_window_time_before_swing`: `lag_multiplier`,
  `lag_offset`, `twist_padding_mode`, `twist_window_padding_ms` via rawget +
  type guards.
- `classes/paladin.lua` `is_twist_impossible` call site: `lag_multiplier`,
  `lag_offset` via rawget.
- `classes/paladin.lua` both twist sound call sites: `twist_sound_choice`,
  `twist_success_sound_choice` via rawget.
- `classes/paladin.lua` next-action gather: `nextaction_reaction_time_ms`,
  `nextaction_cs_max_delay_ms`, `nextaction_filler_mana_consecration`,
  `nextaction_filler_mana_exorcism` via rawget + type guards.
- `classes/paladin.lua`: `twist_success_text_size`, `text_font`, `border_width`
  via rawget + type guards.

### L5 — out of scope (filed, not fixed)
Truthiness-default reads (nil-defaults / feature-silently-off class), explicitly
out of scope per brief. File:line list:
- `main.lua:300` `db_class.class_enabled`
- `main.lua:860` `db.welcome_message`
- `main.lua:2457-2471` `db.form_vis_*` (normal/bear/travel/cat/moonkin/tree/flight)
- `main.lua:2755` `db.dim_oor`; `main.lua:2760` `db.dim_alpha`
- `main.lua:2863,2869` `db.enabled`
- `main.lua:2888` `db.require_in_range`
- `classes/paladin.lua:2005,2012,2158,2166,2214,2238` `db.twist_feedback_enabled`
- `classes/paladin.lua:2140` `db.twist_sound_enabled`
- `classes/paladin.lua:1955-2020` other `db.twist_*_enabled` / `db.twist_*_enabled ~= false` truthiness gates
- (fixed in L5 above: `db.lag_multiplier`, `db.lag_offset`, `db.twist_success_text_size`)
- `classes/paladin.lua:1371-1477` detached-icon coordinate reads (truthiness defaults)
- `option_table_presets.lua`: none beyond L4 (no other db reads in this file).

## Proof

Gate: `bash tests/run.sh` → **54 steps, 0 failed**; luacheck **2 warnings / 0 errors**
(97 files). Run after all edits; re-run green.

Mutation proofs on `/tmp` (single-command copy → mutate → run, directory is
ephemeral per command):
- L1: reverted `play_twist_sound` to `db.sound_channel or "Master"` + unguarded
  `PlaySoundFile` → paladin_state.lua **7 of 1276 checks failed**
  (LATENT L1 pcall + no-plain-read pins).
- L2: reverted `get_class_table` to `profile[self.player_class]` → main_init_state.lua
  **2 of 1056 checks failed** (LATENT L2 runtime + source pins).
- L3: reverted `bar_full_delay` to `db_shared and db_shared.bar_full_delay` →
  main_init_state.lua **2 of 1056 checks failed** (LATENT L3 source pins).
- L4: reverted disabled lambda to `db and db.gcd_marker_offset_mode` →
  options_load_state.lua **1 of 3745 checks failed** (LATENT L4 source pin).

## Pins re-cut

- `tests/paladin_state.lua` LATENT L1 block (4 checks): rawget present; type gate
  present; pcall present; no plain `db.sound_channel or "Master"` read.
- `tests/main_init_state.lua` LATENT L2 runtime check (1 check): `get_class_table`
  returns nil on a `'**'`-shaped profile for a missing class token.
- `tests/main_init_state.lua` LATENT L2/L3 source checks (3 checks): rawget present
  for both; no plain `bar_full_delay` read remains.
- `tests/options_load_state.lua` LATENT L4 source checks (2 checks): rawget present;
  no plain `db.gcd_marker_offset_mode == "Fixed"`/`"Calibrated"` read remains.
No pin count changes in the 54-step harness; step count stays 54/0.

## Live-client needs

- `PlaySoundFile` return arity and accepted channel-name strings on each supported
  client (Era/Anniversary/Titan/Forever/Retail) — cannot be proven offline; the
  pcall guard is the only offline-controllable defence.
- Twist playback path on a real paladin profile: confirm the shipped
  `sound_channel = "Master"` default is honoured and a user-picked channel
  string reaches `PlaySoundFile` on a live client.
- `bar_full_delay` live value (config default 0.05 vs. the 0.5 nil-fallback used
  when no AceDB profile is attached) needs an in-client read of the swing-bar
  full-timer timing.
- `gcd_marker_offset_mode` disabled-state behaviour in the options UI on a live
  client (widget enable/disable without materialising a profile row).
- `get_class_table` nil handling on a live profile with an unknown class token
  (no shipped class module) — offline pin only covers the metatable shape.

## Notes

- No git, no lint-config changes, line endings preserved (LF), version stays 2.1.3.
- `config.lua`, `widgets.lua`, `Libs/`, TOCs, docs, other classes, `.luacheckrc`,
  `tests/run.sh` untouched.
- Central `desks/journal.md` lane row not edited (orchestrator owns it).

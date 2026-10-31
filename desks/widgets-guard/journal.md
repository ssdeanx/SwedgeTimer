# widgets-guard — Journal

## 2026-10-28 — Desk opened; F2.5 latent AceDB sound-preview trap fixed (offline)

- **Worked on:** `widgets.lua`'s `sound_channel()` (pre-fix lines 44-46) handed AceDB
  `'**'`-metatable tables to `PlaySoundFile` unpcall'd. Rewrote the channel resolution to
  `rawget` the class row (and its `sound_channel` leaf), then `rawget` the profile root,
  require a **string**, fall back to the shipped `"Master"` (`widgets.lua:37-72`); wrapped
  both client sound calls in `pcall` (`:149-154`, `:171-177`); guarded a non-string/non-
  number map entry (`:165-169`). Swept the file: no other metatable-triggering read
  remains. Proof added to the suite that covers `widgets.lua` —
  `tests/rotationtext_state.lua` §7b (`:422-692`): real vendored AceDB + shipped defaults
  + real `widgets.lua` in a sandbox, a booted `'**'` profile, the widget's own `OnEnter`
  hover path, paladin regression, throwing-client containment, source pins. Suite 246 →
  286 checks. Mutation proofs M1 (pre-fix read → 10 FAIL, "got table"), M2 (no pcall →
  3 FAIL), M3 (profile rawget only → 3 FAIL) on `/tmp` copies rebuilt from the final tree.
- **Current state:** DONE (offline). Gate `bash tests/run.sh` = 54 steps / 0 failed,
  luacheck 2 warnings / 0 errors in 97 files (baseline unchanged); no red checks to
  attribute (the placement-pin RED the brief warned about had been re-cut before this lane
  started). Report: `bench/widgets_guard_2026-10-28.md`. Version 2.1.3 untouched; scope
  held to the two files.
- **Next step:** (1) live-client pass on the paladin sound previews (argument type is
  proven offline; the client's return value and the audible preview are not). (2) A
  follow-up lane should own `classes/paladin.lua:1151-1157` — `play_twist_sound` still
  does a plain read of the `'**'`-backed class row and calls `PlaySoundFile` unpcall'd on
  the *actual* twist playback path (safe today only because PALADIN ships the string);
  `main.lua:240-244` `get_class_table` has the same plain read. Both outside this lane's
  write scope — listed in the report §6.

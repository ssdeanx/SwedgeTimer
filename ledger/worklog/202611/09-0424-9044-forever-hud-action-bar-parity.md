# 20261109-0424-9044-forever-hud-action-bar-parity: Forever HUD action-bar parity

- **Tags**: HUD, cooldown, GCD, Forever, taint
- **Status**: doing · 2026-11-09 04:42:11 · @taskmaster · eca46018-7d91-4ccd-92cf-2be388cff71c
- **Created**: 2026-11-09 04:24:50 · @taskmaster · eca46018-7d91-4ccd-92cf-2be388cff71c

<!-- Header lines are maintained by the script, fixed order: Tags → Status → Created → Sealed.
     The `- **Tags**: …` line is inserted at the top by new --tags; omitted when there are no tags
     (category goes to the ledger and history only, never into this document).
     The `- **Sealed**: …` line is appended on close. -->

## Background

Operator 2026-11-09: the HUD must behave like an action bar on Forever — GCD, cooldown
swipe, and countdown text in combat/dungeons, with no secret strings or taint. This is
the last offline gate before the operator tests in the client; no other client behavior
may change.

## To Do

- In-client P4/P5 (verification report §10): duration-object sink and binding in a
  restricted Forever moment.
- In-client: ready icons show the GCD sweep; active cooldown icons show the swipe and
  native countdown text; no ADDON_ACTION_BLOCKED / BugSack error; trinket SEC-10 face.
- If P4/P5 fail, capture the exact error; the grey unknown face is the documented
  fallback, never a fabricated timer.

## Next

Run P4/P5 from `bench/hud_forever_verification_2026-11-08.md` §10 in a dungeon pull and
watch the HUD icons. Confirm the custom countdown text still renders after the object
path ends (the dedicated native string separation).

## Process

- SEC-14 string-taint fix: the native `DurationTextBinding` was bound to `icon.text`,
  the same FontString the custom countdown uses. The client attaches a secret Text
  aspect to the binding's string, so a later tainted `SetText` on it is refused
  (`RequiresFontStringTextAccess`). Added a dedicated `icon.native_text` (Forever only)
  and bound the native binding to it; the custom `icon.text` stays untainted. Changed
  sites: `hud.lua` `create_icon`, `prepare_text_binding`, `release_text_binding`, and
  the object-mode text branch.
- Forever GCD provider gap: `forever_guide.get_hud_state` read `self.gcd.expires`; the
  LGC object channel does not set it. Added `GCD_OBJECT_STARTED` / `GCD_OBJECT_OVER`
  callbacks in `main.lua` feeding `self.gcd.gcd_object` / `gcd_on_gcd`; the provider
  supplies `state.cooldown_object` / `state.on_gcd`; `HUD.paint` uses the supplied
  opaque handle for ready slots (no per-slot re-query) and suppresses text on GCD.
- Tests: `hud_state` 1035, `forever_guide_state` 1565, `main_init_state` 1121;
  mutants M2 binding-to-custom-string (fail), M3 supplied GCD ignored (3 fails), M4
  handler no-op (2 fails); full harness 59/0; luacheck 2/0 tree floor.
- UNCONFIRMED: engine acceptance of a secret-valued object from tainted code (P4/P5)
  and the live font-string aspect behavior. The separate string removes the addon-side
  taint hazard, but only the client can prove the native sink.

## Conclusion

Offline HUD hardening is complete: dedicated native text string, Forever GCD object
channel, supplied-handle paint path, and tests/mutations. In-client P4/P5 remain the
only close for the engine behavior.

## Execution Log

<!-- Maintained by the script: appended by new / claim / set / release / log / close. Do not edit.
     Backfill with: progress log --id 20261109-0424-9044-forever-hud-action-bar-parity --note "...". -->
- 2026-11-09 04:24:50 · new · @taskmaster · eca46018-7d91-4ccd-92cf-2be388cff71c · created and claimed
- 2026-11-09 04:42:11 · log · @taskmaster · eca46018-7d91-4ccd-92cf-2be388cff71c · SEC-14 dedicated native_text + provider GCD object + main LGC object callbacks; hud_state 1035, guide 1565, main_init 1121, mutants M2/M3/M4 killed, full 59/0. Next: P4/P5 in a restricted Forever moment.

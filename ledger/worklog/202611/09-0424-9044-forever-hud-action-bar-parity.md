# 20261109-0424-9044-forever-hud-action-bar-parity: Forever HUD action-bar parity

- **Tags**: HUD, cooldown, GCD, Forever, taint
- **Status**: doing · 2026-11-09 15:07:21 · @taskmaster · eca46018-7d91-4ccd-92cf-2be388cff71c
- **Created**: 2026-11-09 04:24:50 · @taskmaster · eca46018-7d91-4ccd-92cf-2be388cff71c

<!-- Header lines are maintained by the script, fixed order: Tags → Status → Created → Sealed.
     The `- **Tags**: …` line is inserted at the top by new --tags; omitted when there are no tags
     (category goes to the ledger and history only, never into this document).
     The `- **Sealed**: …` line is appended on close. -->

## Background

Operator 2026-11-09: the HUD must behave like an action bar on Forever — GCD, cooldown
swipe, and countdown text in combat/dungeons, with no secret strings or taint. This is
the last offline gate before the operator tests in the client; no other client behavior
may change. Later the operator's screenshot showed the working HUD cooldown rendering
`4 Seconds` instead of `4`; the countdown suffix is the one remaining text defect.

## To Do

- In-client P4/P5 (verification report §10): duration-object sink and binding in a
  restricted Forever moment.
- In-client: ready icons show the GCD sweep; active cooldown icons show the swipe and
  native countdown text; no ADDON_ACTION_BLOCKED / BugSack error; trinket SEC-10 face.
- In-client: the native countdown reads `4` (no `Seconds` suffix, no raw float) at four
  seconds, and `2` at 2.518; the same integer numeric style as the readable face.
- If P4/P5 fail, capture the exact error; the grey unknown face is the documented
  fallback, never a fabricated timer.

## Next

`/reload`, pull in a dungeon, and watch an Arcane Shot/ability cooldown: expect the
numeric face `4`, not `4 Seconds`; a 2.518 s value must read `2`, not `2.518`. Then run P4/P5 from
`bench/hud_forever_verification_2026-11-08.md` §10 and confirm the custom countdown text
still renders after the object path ends.

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
- Countdown suffix and precision (2026-11-09): the native text used
  `C_StringUtil.CreateSecondsFormatter`, whose default abbreviation `None` appends the
  interval word ("4 Seconds"); the first unitless swap used an
  `AbbreviatedNumberFormatter`, which exposed raw floats ("2.518"). The final
  `compat.api.create_duration_number_formatter` is a `NumericRuleFormatter` with one rule
  (threshold 0, step 1, rounding Down, format "%.0f"), fed through the already-proven
  `SetFormatter` path: "4", "2". No new `SetTextFormat` surface is used.
- Tests: `hud_state` 1039, `forever_guide_state` 1565, `main_init_state` 1121;
  mutations M12 float rule (1 fail), M9 SecondsFormatter restored (1), M2
  binding-to-custom-string (fail), M3 supplied GCD ignored (3), M4 handler no-op (2);
  full harness 59/0; luacheck 2/0 tree floor.
- UNCONFIRMED: engine acceptance of a secret-valued object from tainted code (P4/P5),
  the live font-string aspect behavior, and the real numeric formatter's output. The
  separate string and unitless formatter remove the addon-side defects; only the client
  can prove the native path.

## Conclusion

Offline HUD hardening is complete: dedicated native text string, Forever GCD object
channel, supplied-handle paint path, and the unitless integer countdown. In-client
P4/P5 and the `4` / `2` text observation remain the only close.

## Execution Log

<!-- Maintained by the script: appended by new / claim / set / release / log / close. Do not edit.
     Backfill with: progress log --id 20261109-0424-9044-forever-hud-action-bar-parity --note "...". -->
- 2026-11-09 04:24:50 · new · @taskmaster · eca46018-7d91-4ccd-92cf-2be388cff71c · created and claimed
- 2026-11-09 04:42:11 · log · @taskmaster · eca46018-7d91-4ccd-92cf-2be388cff71c · SEC-14 dedicated native_text + provider GCD object + main LGC object callbacks; hud_state 1035, guide 1565, main_init 1121, mutants M2/M3/M4 killed, full 59/0. Next: P4/P5 in a restricted Forever moment.
- 2026-11-09 14:40:25 · log · @taskmaster · eca46018-7d91-4ccd-92cf-2be388cff71c · Unitless countdown: AbbreviatedNumberFormatter with ClearBreakpoints fed through the already-proven SetFormatter path; no Seconds suffix. hud_state 1036/0, mutant M9 killed, full 59/0. Next: reload and confirm 4 on a cooldown.
- 2026-11-09 15:07:21 · log · @taskmaster · eca46018-7d91-4ccd-92cf-2be388cff71c · Integer countdown: replaced the raw-float AbbreviatedNumberFormatter with a NumericRuleFormatter rule (threshold 0, step 1, rounding Down, format %.0f) via the proven SetFormatter path. hud_state 1039/0, M12 killed, full 59/0. Expected 4 and 2, never 4 Seconds or 2.518.

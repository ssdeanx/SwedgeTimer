# Brief — docs-release (2026-10-28)

Desk: `docs-release`. Final release-notes pass for **version 2.1.3 — the version number does
NOT change** (operator: "we are staying on same version"). This lane writes prose only.

## Write scope

- `CHANGELOG.md`
- `README.md`

Do NOT touch: any `.lua`, any TOC, `AGENTS.md`, `TESTING.md`, `docs/`, `bench/`, `desks/`,
`hands-up.md`, `.gitattributes`, `.gitignore`, `.luacheckrc`, `tests/`.

## What must be true in the notes

1. **Read the independent audit's §P5-3 first** — `bench/publish_audit_2026-10-28.md`,
   section `P5-3` (in the SUPERSEDING AUDIT). It gives the exact MUST-CLAIM and
   MUST-NOT-CLAIM lists. Follow it; it exists because the current `CHANGELOG.md:33-36`
   sentence about the power bar ("offhand when used") is now **wrong**.
2. **Wave scope to describe, from the lane reports** (read them, do not invent):
   - `bench/hunter_tint_2026-10-28.md` — hunter main-hand fill can no longer be recoloured by
     ranged play; the Raptor/Steady tint requires a live melee cycle and every clear path
     repaints. Defaults unchanged (Raptor ON, Steady OFF).
   - `bench/bars_decouple_2026-10-28.md` — ranged/offhand bars are activity-driven (a real
     shot/swing opens a window of 2 cycles; combat alone shows nothing); Shoot/Throw/Shoot
     Wand no longer reset the melee swing; a generic shot→melee-reset guard on the engine;
     offhand renders at the mainhand size; the power bar owns the row under the melee stack.
   - `bench/layout_finish_2026-10-28.md` — ranged placement rule; `melee_bar_height` pair key
     for MH+OH; `/st diag` BAR STATE line; the appearance-migration discovery.
   - `bench/appearance_fix_2026-10-28.md` — the one-time opaque-backdrop migration now
     actually runs on a live profile (rawget/rawset, `== true` marker).
   - `bench/ranged_forced_2026-10-28.md` (SUPERSEDING REPORT) — placement is FORCED: every
     ranged-owning class is moved into the new layout once, dragged/scaled rows included;
     the power-bar row is never given up.
   - `bench/widgets_guard_2026-10-28.md`, `bench/paladin_sound_2026-10-28.md` — AceDB
     metatable-trap hardening (sound preview, twist playback).
   - `bench/ui_truth_diag_2026-10-28.md` — offhand Width widget now truthful; `/st diag`
     gains the power line, per-hand gate/receipt/hide-reason fields and named quarantine
     sites.
   - `bench/hunter_ui_driver_2026-10-28.md` — the hunter visual set (cast bar, range helper,
     badges) no longer dies with the hidden ranged bar.
   - `LibGlobalCooldown.lua` (operator-reported): the Classic Era `GetCombatRating(CR_HASTE_SPELL)`
     crash — index resolved to the literal 20 with pcall guards.
3. **Honesty rules:** no in-client claims (nothing in this wave has been proven in a client);
   no version bump; no feature that the code does not do; do not claim Retail/other-class
   support that the audit said is not there (Retail MONK/DH/EVOKER option getters can raise).
4. **Style:** match the existing `CHANGELOG.md` structure (`## [2.1.3]` already exists — extend
   its Added/Changed/Fixed/Hardening subsections; do not create a new version heading).
   `README.md`: add only what is genuinely new/user-visible (power bar row ownership, ranged
   placement, melee pair height, the improved `/st diag`), keep it short.
5. Preserve the files' existing line endings.

## Rules

- Load and follow the lane skills first: `bench-read`, `desk-open` (desk `docs-release`),
  `desk-journal`, finish with `signal-write`.
- Read the files you edit (both) before editing them.
- No git. `bash tests/run.sh` must stay green (prose-only change: 54 steps / 0 failed;
  if a docs mention is cross-checked by a test, say which and why it still passes).
- Report to `bench/docs_release_2026-10-28.md`; journal at `desks/docs-release/`.

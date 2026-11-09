# secret-hud-fix — Journal

## 2026-11-06 — Desk opened: SEC-10 restricted trinket HUD face (WoW Forever)

- **Purpose:** fix audit SEC-10 (`bench/secret_consumers_audit_2026-11-06.md`): on the
  Forever client a restricted item-cooldown read degrades to `0,0,0`; the HUD's
  `trinket_has_on_use` read `use_enable == 1` → false, so an equipped on-use trinket's
  HUD slot silently disappeared. compat's `api.GetInventoryItemCooldown` now returns an
  additive fourth `restricted` value (true when any raw field was secret) — consume it
  in the HUD: tri-state on-use detection, restricted state keeps the slot visible in the
  existing grey/no-swipe/no-text face, readable passive still hides, readable on-use still
  shows. Optional once-per-session chat notice.
- **Scope (write):** `hud.lua`, `tests/hud_state.lua`, `desks/secret-hud-fix/**`, one NEW
  report `bench/secret_hud_fix_2026-11-06.md`. No other file, no git, no version fields.
- **Lane skills:** bench-read, desk-open, desk-journal, signal-write (loaded this session).
- **Priors read:** `bench/secret_consumers_audit_2026-11-06.md` (executive table + L5 +
  §3 verified-clean "Forever HUD is restricted-aware"), `bench/secret_guide_fix_2026-11-06.md`
  §2 (the fourth return contract + §3 "SEC-10 is the secret-hud-fix lane's"),
  `bench/secret_api_matrix_2026-11-06.md` §6 (sinks: CooldownFrame SetCooldown is
  AllowedWhenUntainted → the swipe cannot be driven from a restricted read; the unknown
  face is the correct answer), `desks/journal.md` secret-wave dispatches.
- **Baseline verified:** `tests/hud_state.lua` 859 checks PASS; `forever_hud_gate_state`
  174/0; `secret_guard_state` 524/0; tree 2.1.8; `bash tests/run.sh` 57/0 (Lead-stated and
  re-checked); luacheck 2/0; hud.lua/tests/hud_state.lua are LF.
- **Next step:** red-first pins (§20b) + fixture secret modeling, then the HUD fix.

## 2026-11-06 — [signal:done] SEC-10 fixed, red-first pins + 3 mutation kills

- **Worked on:** `hud.lua` — `trinket_has_on_use`/`HUD.trinket_usable` now tri-state
  (true readable on-use / false readable passive / nil restricted-unknown, reading compat's
  fourth return); `HUD.trinket_state` resets `s.restricted` each tick, sets it on the nil
  branch, gates the on-use swipe on `not s.restricted`, and fires a once-per-session
  `st.utils.print_msg` notice; `HUD.icon_should_show` returns
  `HUD.trinket_usable(...) ~= false` (only a confirmed passive hides). `HUD.paint` was
  reused unchanged — its restricted face already skips the swipe/text and desaturates.
  `tests/hud_state.lua` — added real secret modeling (`env.issecretvalue` + per-build
  `SECRETS`, raw cooldown fixture returns `secret(900301..3)` when
  `item_cooldowns[slot] = { restricted = true }`) so the REAL compat wrapper produces
  `0,0,0,true`; new §20b (36 checks): restricted slot shown + `s.restricted` + no
  swipe/text + greyed through the real driver; paint defence-in-depth on a timing-carrying
  restricted state and a fresh icon (no SetCooldown at all); readable passive hides;
  readable on-use shows; flag does not latch; notice once-per-session; known-proc control.
- **Current state:** red-first 10/895 failed (exactly the intended pins), then
  `tests/hud_state.lua` = **895 checks PASS** (baseline 859); `forever_hud_gate_state`
  174/0; `secret_guard_state` 524/0; `bash tests/run.sh` = **57 steps, 0 failed**;
  luacheck on the two changed files 0/0 (tree floor 2/0 in 100 files); LF preserved;
  `luac5.1 -p` clean. Mutations on fresh `/tmp` source copies: M1 restricted→false/hide
  → 5 fails; M2 paint ignores the restricted gate (swipe/text painted) → 5 fails;
  M3 ignore the fourth return → 10 fails. Report: `bench/secret_hud_fix_2026-11-06.md`.
  No compat/forever_guide/version/TOC/git touched; no in-client proof claimed.
- **Next step:** Lead re-runs the full gate (already 57/0 here) and the docs/mnemon pass;
  optional follow-ups in the report — L5 `?` marker (operator display decision), L4 diag
  restricted-cooldown receipt, a restricted trinket leg in forever_hud_gate_state (filed,
  out of scope).

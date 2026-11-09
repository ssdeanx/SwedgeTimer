# hud-cooldown-fix — Journal

## 2026-11-08 — Desk opened (task t3, `swedge-forever-hud` team, attempt 1)

- **Purpose:** writer lane. Implement the Forever-only secret-safe HUD cooldown/GCD path
  (native duration-object pass-through, native countdown text, GCD on ability icons),
  plus secret/cache hardening of `hud.lua` / `compat.lua` / `LibGlobalCooldown.lua`.
  Tests red-first-equivalent (mutant-proven), one bench report, this journal, one done
  signal. **No git, no version, no TOC/config/options/main/bars/classes/docs edits.**
- **Scope:** `hud.lua`, `compat.lua` (additive helpers), `LibGlobalCooldown.lua`,
  `tests/hud_state.lua`, `tests/forever_secret_compat_state.lua`,
  `bench/hud_forever_cooldown_2026-11-08.md`, `desks/hud-cooldown-fix/**`.
- **Inputs read first:** `bench/forever_hud_api_2026-11-08.md` (T1 contract, whole file),
  `bench/briefs/brief_hud_cooldown_impl_2026-11-08.md`, `hud.lua` header + paint path,
  `compat.lua` cooldown/secret wrappers, `LibGlobalCooldown.lua`, prior secret bench
  reports, `AGENTS.md`, `desks/journal.md` tail, `bench/lessons.md`,
  `bench/secret_hud_fix_2026-11-06.md`, `bench/secret_consumers_audit_2026-11-06.md`.
- **Client proof source:** T1's `origin/forever` citations; no new web search, no
  `origin/forever` checkout. Runtime-only facts remain UNCONFIRMED with `/run` probes.

## 2026-11-08 — [signal:done] Forever secret-safe cooldown/GCD + cache hardening delivered

- **Worked on:** the whole t3 work list.
  1. **Cooldown swipe:** while the provider flags `restricted`, `HUD.paint` acquires
     `C_Spell.GetSpellCooldownDuration(slot spell, ignoreGCD=false)` through the new
     `api.get_spell_cooldown_duration` and hands the opaque handle to
     `CooldownFrame:SetCooldownFromDurationObject(object, true)`; no value is ever read
     out of the object. Readable states keep the exact old numeric path (Forever
     included). Trinkets keep SEC-10 (no item duration-object API on this client).
  2. **Countdown text:** `C_DurationUtil.CreateDurationTextBinding` per icon, fed the same
     handle and a plainly-configured `C_StringUtil.CreateSecondsFormatter`; the warn
     colour is a `C_CurveUtil.CreateColorCurve` step curve evaluated by the client against
     `RemainingDuration`. The 2 s GCD rule is enforced from the plain `isOnGCD` field.
     `GetText`/`GetFormattedText` are never read.
  3. **GCD:** `LibGlobalCooldown.poll_gcd` gains a Forever-only + probe-gated object channel
     (`lib.gcd_object`, plain `lib.gcd_on_gcd`, additive `GCD_OBJECT_STARTED`/
     `GCD_OBJECT_OVER` callbacks) and clears/skips the numeric timing cache on a restricted
     read. The HUD paints the GCD from the same per-spell object (`ignoreGCD=false`),
     which is the only wiring reachable without touching `main.lua` (out of scope).
  4. **Cache hardening:** `HUD.known_names` (secret id/name refused), `known_cache`
     (exposed as `HUD.known_cache`; entries re-proved plain before read, poisoned entries
     dropped), `HUD.trinkets`/`TRINKET_STATE` (poisoned record dropped before compare),
     `PREVIEW_STATE` (`restricted` reset), a new SEC-13 state scrub at the
     provider→paint boundary, and boolean-field guards in `paint` (`usable`, `in_range`,
     `glow`, `desaturate`, `reverse`, `hidden`, `texture`) so a secret boolean lands on the
     unknown/no-cue face.
- **Deviations reported (not silent):** T1's trinket fourth-return claim does not apply to
  this tree (compat reads three values already; contract change forbidden by the brief —
  documented in the bench report §6.1); `UNIT_SPELLCAST_INTERRUPTED` keeps its pinned
  behaviour because `tests/secret_guard_state.lua` is cross-lane (§6.2); GCD wiring split
  between HUD (paint) and LGC (state channel) (§6.3); native restricted text rounding can
  differ ≤1 s (§6.4).
- **Evidence:** `tests/hud_state.lua` 1 024 checks PASS (was 893);
  `tests/forever_secret_compat_state.lua` 250 checks PASS (was 177); full
  `bash tests/run.sh` **59 steps, 0 failed**; `luacheck .` 2 warnings / 0 errors in 105
  files (both pre-existing `hunter_ui.lua`, tree floor); `luac5.1 -p` clean; local budget
  hud.lua 59/190. Mutation proofs: 8 single-site mutants, 7 kill the suite (exit 1, exact
  counts in the report §5); M5 (the SEC-13 state scrub) survives offline and is documented
  as redundant-with-paint offline / load-bearing on the real client.
- **Current state:** implementation + tests complete, full harness green on the final
  tree. In-client probes P3/P4/P5/P6/P7/P8/P10 (report §7) remain the only close for the
  runtime unknowns (does the engine accept a secret-valued object from tainted code; do
  native numbers render) — operator action, not a code blocker.
- **Next step:** t5 verification lane (independent review + re-run); no further work from
  this desk unless the verifier files a finding.

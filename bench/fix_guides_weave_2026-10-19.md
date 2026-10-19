# Buildout: fix-guides-weave (2026-10-19)

Lane: writer. Scope executed per `bench/briefs/brief_fix-guides-weave_2026-10-19.md`.
Baseline before edits: `bash tests/run.sh` → 35 steps, 0 failed; luacheck 2/0.
Final: **35 steps, 0 failed; luacheck 2 warnings / 0 errors** (floor held).
No git run. No out-of-scope file touched (`main.lua`, `bars.lua`, `swing_source.lua`,
`enemy_swing.lua`, TOCs, version fields, CHANGELOG untouched — reconciliation is with
fix-engine-dispatch; nothing to hand up).

## Files changed

| File | Change |
|---|---|
| `weave.lua` | H4: unknown cast separation + nil-safe `is_clipped` + doc |
| `nextaction.lua` | M6: `inputs_unknown` in/out threading (evaluate, evaluate_fcfs, Retail) |
| `nextaction_ui.lua` | M6: "…" render state + stale-gather fallback flags unknown |
| `compat.lua` | M5: `api.auras_may_be_secret()` observability probe (E2 untouched) |
| `classes/paladin.lua` | M3 counter+notice, M4 band state, M5 unknown latch+text, M6 gather bit, H6 doc, G3/G6 wiring notes |
| `classes/shaman.lua` | H4: hide markers/positions on unknown cast, catalogue-retry acceptance note |
| `classes/hunter.lua` | **no change**: R4 line `classes/hunter.lua:1068` is already `st.lust_supported == true`; a pin now holds it (below) |
| `tests/weave_state.lua`, `tests/nextaction_state.lua`, `tests/guide_contract.lua`, `tests/secret_guard_state.lua`, `tests/paladin_state.lua`, `tests/shaman_state.lua`, `tests/hunter_state.lua`, `tests/smoke.lua` | pins for every item below |

Line endings verified: `nextaction.lua` / `nextaction_ui.lua` / `classes/paladin.lua`
still 100% CRLF (CR count == line count); all other touched files stay LF as shipped.

## Item closure

### H4 — missing cast time no longer degrades to instant
- `weave.lua:207` `get_effective_cast_time`: base non-number/NaN/<=0 → **nil** (unknown);
  instant flag and MW<=0 still return the legitimate 0.
- `weave.lua:225` `get_marker_fraction`: unknown cast → **nil** (no whole-swing-safe marker).
- `weave.lua:276` `is_clipped`: unknown marker never asserts a clip (nil-safe compare).
- `classes/shaman.lua:2063`: marker trio hides on nil marker fraction;
  `classes/shaman.lua:1790`: spell-position row hides the slot instead of `nil*width`.
- Harness: `tests/weave_state.lua` 441 checks PASS (new H4 pins + G5 composition);
  `tests/shaman_state.lua` 393 checks PASS (§11b pins).
- Mutation proofs (on `/tmp/opencode/mut_guides` copies, pristine restored):
  base `return nil`→`return 0` → `FAIL cast: base 0 is UNKNOWN -> nil (H4, was 0)` (rc=1);
  marker nil-guard removed → `FAIL marker: nil cast -> nil (UNKNOWN, H4; was 1)` (rc=1);
  shaman hide-guard disabled → `FAIL H4: the main marker hides on an unknown cast` (rc=1).

### M6 — `inputs_unknown` bit
- Engine: `nextaction.lua:376` (evaluate) and `nextaction.lua:857/909` (evaluate_fcfs)
  thread `inputs.inputs_unknown == true`; Retail reports `true` (`nextaction.lua:369`).
- Provider: `classes/paladin.lua:2482` sets it when the swing record is unusable;
  `classes/paladin.lua:2749` copies it to the display table.
- Frame: `nextaction_ui.lua:530` suppresses all advice targets and paints the label "…"
  (latched, no per-tick SetText); `nextaction_ui.lua:707` flags a non-table gather as unknown.
- H6-half (extend, not re-derive): the frozen-spec field-presence matrix now lives at
  `classes/paladin.lua:1625-1635` (speed/G/seal provider guarantees with file:line cites).
- Harness: `tests/nextaction_state.lua` 449 PASS, `tests/guide_contract.lua` 693 PASS
  (gather bit, frame "…" render + latch).
- Mutations: engine bit forced false → `FAIL M6: an explicit inputs_unknown=true threads into out` (rc=1);
  UI `unknown = false` → `FAIL M6: unknown inputs light no action slot` (rc=1).

### M3 — unmatched twist-proc payload observability
- Counter + one-time notice at threshold 3: `classes/paladin.lua:564,651-657`.
  `/st diag` is outside this lane (diag.lua not in scope), so the counter lives on the
  addon session state and the sustained case is announced once in chat — same
  visible-degradation shape as the R3 badge (`classes/paladin.lua:1311`).
- Harness: `tests/paladin_state.lua` §14; mutations: counter frozen → `FAIL M3: a payload with no id and no name is counted` (rc=1).

### M4 — distinct "seal data unknown" band state
- `classes/paladin.lua:796` constant, `:802` setter, `:1311-1322` state decision,
  `:1415-1427` degraded band (full width, alpha 0.10, text "seal data unknown").
  The mirror-failure half is **cited, not fabricated**: compat's whole-entry secret
  degrade (`compat.lua:440-463`) makes a restricted row read absent, so a broken mirror
  and a genuine no-seal state are indistinguishable — that case stays the normal hidden
  look; the new state covers seals-readable + swing-unusable (dead/stub engine).
- Harness: `tests/paladin_state.lua` §15 (degraded shows, single/none-seal hides).
- Mutations: `swing_usable=true` → geometry error rc=1; text constant changed →
  `FAIL M4: the band says why it cannot time a twist (got twist?, want seal data unknown)` (rc=1).

### M5 — lust-unknown affordance (E2 untouched)
- `compat.lua:549` `api.auras_may_be_secret()`: pcall'd `C_Secrets.ShouldAurasBeSecret`;
  true/false only when the client answers a boolean, nil when absent/throws (classic no-op).
- Consumer: `classes/paladin.lua:1080` sets `twist_lust_unknown` when the scan is
  inconclusive under that regime; the band then shows "lust unknown" (`:1321,1338`).
  Behind the existing `twist_lust_override_enabled == true` opt-in only.
- Harness: `tests/paladin_state.lua` §16, `tests/secret_guard_state.lua` 13b (256 checks).
- Mutations: probe forced nil → `FAIL M5: the secret regime marks the lust reading unknown` (rc=1);
  probe true on absent API → `FAIL M5 probe: no C_Secrets reads nil (control)` (rc=1).

### R4 — lust gate standardised
- Paladin `classes/paladin.lua:1101` already `st.lust_supported == true`; hunter
  `classes/hunter.lua:1068` already `== true` — **no hunter code change needed**.
- Harness: `tests/hunter_state.lua` 453 PASS adds the static spelling pin + a truthy
  non-true runtime pin (`R4: a truthy non-true gate never arms the scan`).

### Shaman catalogue-retry observability
- Accepted as designed, documented in-place: `classes/shaman.lua:313-319` — after H4 an
  unresolved cast is unknown and every widget hides, so silence + throttled retry is the
  safe direction; no chat/diag notice for a low-level character whose book is cold.
- Harness: `tests/shaman_state.lua` §11c (nil family + retry stamp `clock + 5`, quiet).
  Mutation: retry stamp dropped → `FAIL catalogue miss: the retry is throttled, not spammed` (rc=1).

### Proctor G1 — Cata/Mists runtime family + engine selection
- `tests/smoke.lua` adds project=14/19 profiles (family, `is_mainline==false`,
  `gcd_probe_spell_id==29515`, lust gate true, rank resolution both directions,
  `swing_source.available == false`) and a read-only `main.lua` boot harness
  (compat + swing_source + main; nothing in main/bars/tocs touched) asserting
  `swing_engine == "inert-standin"` with the lib absent and `"vendored-lib"` as control.
- Mutation: main ladder branch forced → `FAIL cata(14): the lib-absent boot selects the inert stand-in (got forever-source, want inert-standin)` (rc=1).

### Proctor G4 — player combat-enter/exit continuity
- Same boot: `PLAYER_REGEN_DISABLED/ENABLED` flip `in_combat` exactly, keep the same
  mainhand record object (speed/start/ends_at/is_full untouched) and fire the class
  `on_combat_exit` hook once per exit.
- Mutation: `PLAYER_REGEN_ENABLED` clears mainhand → `FAIL G4: combat exit keeps the mainhand record (got nil, want table:...)` (rc=1).

### Proctor G2 — lust → 0.6× window → band composition
- `tests/paladin_state.lua` §17 first block: base band 200×(0.4/3), live Bloodlust band
  200×(0.24/3) through the real `on_bar_update`; Era never narrows.
  Mutation: `LUST_TWIST_WINDOW_SCALE` 0.6→1.0 → `FAIL G2: live Bloodlust narrows the drawn band` (rc=1).

### Proctor G3 (+G6 folded) — lag calibration wiring / deadzone independence
- `tests/paladin_state.lua` §17 second block: defaults 1.4/15 on 100 ms world latency →
  0.5085; custom 2.0/0 → 0.54; nil keys fall back to 1.4/15; varying
  `deadzone_scale_factor` + `enable_deadzone` moves nothing; static pins that the twist
  path reads the lag keys and never references `deadzone_scale_factor` anywhere in
  `classes/paladin.lua`.
  Mutations: default 1.4→1.0 → `FAIL G3: nil lag keys fall back to 1.4/15 (got 0.4805, want 0.5085)` (rc=1);
  deadzone read injected → `FAIL G6 wiring: the paladin twist path never references the deadzone calibration` (rc=1).

### Proctor G5 — weave cross-term composition (3 cases, end to end)
- `tests/weave_state.lua` G5 block: 0-stack LB baseline → marker/`wait`/no prompt;
  3 stacks + 30% haste + 100 ms latency → effective/marker/`ready`/`clip`/`safe_start_in`;
  5-stack instant short-circuit → marker 1.0/`ready`/prompt.

## Harness (final, in-tree)

```
35 steps, 0 failed
luacheck . (Total: 2 warnings / 0 errors in 71 files)
```

Per-suite counts of the touched suites: smoke 183, weave 441, shaman 393, paladin 231,
nextaction 449, guide_contract 693, hunter 453, secret_guard 256.

Mutation battery: 15/15 bitten on `/tmp/opencode/mut_guides` (plus 3 clean-assertion
re-runs); post-restore copy sanity all PASS. Script: `/tmp/opencode/muts_guides.py`.

## Residuals / notes for the orchestrator

- `diag.lua` was out of scope, so M3's counter and M5's regime flag are not yet rendered
  by `/st diag`; both are session state + visible affordance in the meantime.
- `practice.lua` consumes `get_marker_fraction` and already treats nil as unscored
  (`practice.lua:2436-2438`) — no change needed; full suite green.
- No default-visible change beyond the intended degraded states (M4 band only when
  seals readable + swing unusable; M5 text only behind the existing opt-in key).

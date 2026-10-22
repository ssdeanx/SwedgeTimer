# Bars Print Policy — Journal

## 2026-10-19 — Desk opened
- **Purpose:** close audit finding **F12** (`bench/deep_audit_2026-10-19.md:30`) in
  `bars.lua` — the chat-output policy of the swing-timer bar module — and sweep
  `bars.lua` for any other bare-global `print` or unprotected error path.
- **Scope:** `bars.lua` (production) and `tests/bars_state.lua` (pins only).
  Sibling lanes own `main.lua`, `diag.lua`, `compat.lua`, `hud.lua`, the class files,
  the practice/design modules, options/config, `tests/run.sh`, the TOCs and the docs.
- **Rules carried:** wire-not-strip (fix, or KEEP with a written rationale — never
  silence with `_`); nil-safe; no default-visible change; preserve each file's line
  endings (verified per file, not assumed); harness + mutation proofs on `/tmp/opencode`
  copies; no git; no lint-config changes.
- **Next step:** read `bench/deep_audit_2026-10-19.md` F12, verify the finding's premise
  against the in-tree source, land the fix plus pins, prove it on `/tmp/opencode` copies
  and file the report on the bench.

## 2026-10-19 — F12 premise verified against the source (READ-ONLY, before any edit)
- **F12's location claim is factually wrong.** `bars.lua:13` reads
  `local print = st.utils.print_msg`, so the `print(...)` at `bars.lua:1185` resolves to
  the addon's chat path, **not** to the raw global. The auditor's own Limitations section
  lists "global `print`" as `UNVERIFIED-HERE` (`bench/deep_audit_2026-10-19.md:99`) — the
  finding was filed without that re-verification.
- **The underlying policy gap is still real.** `bars.lua:1185` was the only *live*
  (non-debug) call in the whole live tree that reached the chat path through the
  ambiguous `print` identifier. Every sibling design-mode message uses the explicit
  form: `designmode.lua:575`, `designmode.lua:887`, `designmode.lua:892` all call
  `st.utils.print_msg("Design mode: ...")`, and `bars.lua:1224` already uses
  `st.utils.print_msg(...)` directly in this very file.
- **Load order verified:** `utils.lua` is TOC line 37/38 and `bars.lua` line 56/57 in all
  7 tocs, so the alias at `bars.lua:13` was never nil.
- **Line endings verified per file** (lesson "verify line endings per file"): `bars.lua`
  is LF (0 CR bytes in 1224 lines), `tests/bars_state.lua` is LF (0 CR in 2509).
  `utils.lua` and `main.lua` are CRLF — untouched by this lane.

## 2026-10-19 — F12 fixed + bars.lua output-policy sweep
- **Worked on:** F12 (`bench/deep_audit_2026-10-19.md:30`) plus the dispatch's sweep of
  `bars.lua` for bare-global prints and unprotected error paths. Report:
  `bench/bars_print_policy_2026-10-19.md`.
- **Files changed (only these):** `bars.lua` (policy comment replacing the `local print`
  alias; the F12 call site now `st.utils.print_msg`; 6 commented-out debug prints renamed
  to the same path; a `get_cells` nil-guard for degenerate geometry; the LibDataBroker
  feed wrapped in the module's own `run_guarded`) and `tests/bars_state.lua` (new
  section 7, 8 checks, 838 → 855; the sandbox now spies the client's global `print`).
- **Current state:** harness **40 steps, 0 failed**; luacheck **2 warnings / 0 errors**
  (the ledger floor — this lane's two files are 0/0). Mutation proofs on `/tmp/opencode`
  copies: **5/5 killed** (`/tmp/opencode/mut_f12.py`); the M1 copy also fails the full
  harness end to end (40 steps, 1 failed). The bench report is filed.
- **Not done (out of scope, routed in the report §4):** `config.lua:74` and
  `config_presets.lua:1393` still hold live (debug-gated) bare-global `print` calls, and
  `main.lua:50` still holds the `local print = st.utils.print_msg` alias shape this lane
  removed from `bars.lua`. Those files belong to sibling lanes — reported, not touched.
- **Next step:** nothing owed by this desk. If the operator rules that the `st.debug`
  global prints in the config lane must also move to `st.utils.print_msg`, that is a
  one-line change per file in that lane (the pattern is documented in
  `bench/bars_print_policy_2026-10-19.md` §4).

## 2026-10-19 — [signal:done] F12 closed + bars.lua output-policy sweep
- Signal file: `desks/bars-print-policy/.signals/2026-10-19T000000Z-done.json`
  (`run_id: f12-bars-print-policy-2026-10-19`). Harness 40/0, luacheck 2/0 (floor held),
  mutations 5/5 killed. Benchmark artifact: `bench/bars_print_policy_2026-10-19.md`.
- The signal's escalation field carries the routing note for the config lane
  (`config.lua:74`, `config_presets.lua:1393`) and the `main.lua:50` alias observation —
  out of this desk's scope, reported not touched.



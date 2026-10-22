# print-policy-tail — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Close the last bare-global `print` calls routed out of the bars lane —
  `main.lua`'s `local print` alias + trailer, and `config_presets.lua`'s debug trailer.
- **Scope:** `main.lua`, `config_presets.lua`, and the pins in `tests/main_init_state.lua`
  / `tests/options_load_state.lua`. `config.lua` is a running lane's file — filed, not
  touched.
- **Next step:** read `bench/bars_print_policy_2026-10-19.md` §4, apply the bars-lane
  pattern, pin it.

## 2026-10-19 — [signal:done] print-policy tail closed (offline-verified)
- **Worked on:** read the bars-lane artifact (§4 listed `config.lua:74`,
  `config_presets.lua:1393`, `main.lua:50` + `main.lua:1893` as the out-of-scope
  remainder) and re-verified each against the source before editing. Two of the three
  were this lane's; `config.lua` was not.
  - **`main.lua`**: removed the `local print = st.utils.print_msg` alias (line 50),
    replaced by the file's chat-output policy note (4 comment lines); routed the
    `st.debug`-gated module trailer (`-- Parsed main1.lua module correctly`) through
    `st.utils.print_msg`; renamed the **nine** commented-out debug prints to
    `st.utils.print_msg(...)` so a re-enabled comment cannot reach the raw global now
    that the alias is gone. CRLF preserved (1900 CR bytes before and after).
  - **`config_presets.lua`**: routed the `st.debug`-gated trailer through
    `st.utils.print_msg`. LF preserved (0 CR bytes before and after). The `st.debug`
    gate is untouched on both, so **no default-visible change** (`st.debug` is false,
    `utils.lua:65`).
  - **Pins**: `tests/main_init_state.lua` new section 18 (4 checks, 764 → 768) and
    `tests/options_load_state.lua` new section 21 (4 checks, 3252 → 3256). Both suites
    gained a spy on the **client's global print** (`sb.raw_prints` / `env.print`), so a
    module that reaches the global is an assertion, not console noise. The
    `st.debug`-gated trailers are unreachable by default, so `main_init_state`'s
    sandbox gained an `opts.debug` switch that flips `st.debug = true` after
    `utils.lua` loads but before `main.lua` loads — without it the runtime pin would
    have been vacuous. `options_load_state`'s runtime half uses a **dedicated** sandbox,
    not the shared `load_modules()`, because the shared loader also pulls in
    `config.lua` (still on the old path) and would have made this lane's verdict depend
    on another lane's file.
- **Current state:** `bash tests/run.sh` **41 steps, 0 failed** in-tree at the time of
  the lane's own validation. `luacheck .` **2 warnings / 0 errors in 82 files** — the
  ledger floor, held (both warnings pre-existing, in sibling-lane files; `luacheck` on
  this lane's four files alone reports **1 warning / 0 errors**, the pre-existing
  `table.pack` one). Owning suites: `tests/main_init_state.lua` **768 checks, 0 failed**,
  `tests/options_load_state.lua` **3280 checks, 0 failed**. Mutation proofs on
  `/tmp/opencode` copies (`/tmp/opencode/mut_print.py`): **7/7 killed**, each for the
  named output-policy pin, and the end-to-end harness on the M2/M5 copies reports
  exactly one failing step each (the base copy is 41/0 green).
  **Concurrent-lane crossfire, proven not mine:** a sibling lane was landing
  `classes/*.lua`, `practice_ui.lua` and `tests/practice_state.lua` /
  `tests/practice_ui_state.lua` throughout, so harness failures appeared and vanished
  with a *different* suite failing each run. The lane's exact `main.lua` +
  `config_presets.lua` hunks were reverted programmatically in a copy of the current tree
  (`/tmp/opencode/revert_lane.py`) and the harness re-run:
  `tests/hunter_guide_state.lua` failed **identically** in the reverted copy
  (`pop: the pops are a TBC rotation (got S, want nil)`), while this lane's two suites
  failed **only** in the reverted copy — the pins catch this lane's edits and nothing
  else.
- **Filed for the owning lane:** `config.lua:82` (the bars lane filed it as line 74; a
  running lane has since edited the file above it) —
  `if st.debug then print('-- Parsed config.lua module correctly') end` is a live bare
  global print; `config.lua` has no `print` alias (its line 9 one is commented out). Out
  of scope here (running lane). One-line fix of exactly the same shape as
  `config_presets.lua:1393`. Recorded in `bench/print_policy_tail_2026-10-19.md` §5.
- **Artifacts:** `bench/print_policy_tail_2026-10-19.md`; signal
  `desks/print-policy-tail/.signals/2026-10-19T21-05-00Z.json`.
- **Scoped final validation:** every suite that loads a file this lane changed is
  green — `smoke`, `main_init_state` (768 checks), `options_load_state` (3280 checks),
  `bars_state`, `hud_templates_state`, `practice_progress_state`, `secret_guard_state`,
  `wiring_check`, `toc_check`, `diag_state`, `design_state`. `luacheck .` = **2 warnings
  / 0 errors in 82 files** (ledger floor held); `luacheck` on this lane's four files
  alone = **1 warning / 0 errors** (the pre-existing `table.pack` one, present in
  `HEAD` too).
- **Next step:** orchestrator validation (harness + mutation proofs). The tree was moving
  during this session (a concurrent lane was landing `classes/*.lua`,
  `practice_ui.lua` and `tests/practice_state.lua` / `tests/practice_ui_state.lua`
  throughout); every number above was re-taken from the final tree, and the
  crossfire was proven not to be this lane's (see Current state).

# perf-audit — Journal

## 2026-11-06 — Desk opened: swing-bar per-tick cost audit (WoW Forever focus)

- **Purpose:** audit the current per-frame/per-tick cost of the swing bar system
  (mainhand/offhand/ranged) on the current tree, especially on WoW Forever (Camelot
  1.60.1, Mainline-code, `st.is_mainline = true`), and produce a minimal, testable
  optimization plan. Operator complaint: "the bars are taking up a lot of resources and
  little buggy on wow forever".
- **Scope:** `bars.lua` tick + `set_bar_texts`, `main.lua` range poll / visibility pass,
  `hunter_ui.lua` tick path (operator's class), `hud.lua` + `nextaction_ui.lua` +
  `ldb.lua` only where the bar tick calls them, Forever-specific compat cost. NOT the
  whole addon; no practice/guides/enemy-swing deep dive.
- **Lane skills loaded:** bench-read, desk-open, desk-journal, signal-write (all four
  present).
- **Priors read:** `desks/journal.md` (central ledger tail + the 2026-10-25 perf entry),
  `bench/lessons.md`, `bench/audit_core_perf_2026-10-25.md` (O1-O10, R1-R5),
  `desks/forever-secrets/journal.md` (Forever restricted-read facts), `AGENTS.md`.
- **Baseline verified this session:** tree at **2.1.8** (all 7 TOCs + `main.lua:5`; the
  only `main.lua` diff vs 2.1.7 is that version line — checked with `git diff -U0`),
  `bars.lua` mtime unchanged (2026-11-04 00:08), `bash tests/run.sh` → **57 steps, 0
  failed**, luacheck **2 warnings / 0 errors in 100 files**. Matches the brief.
- **Worked on:** re-grepped every symbol from the 2026-10-25 brief in the current tree
  (all line numbers had moved) and counted the tick path by hand:
  - `bars.lua:1124-1323` `onupdate_common` — ≈19 client calls/tick/hand with shipped
    defaults (6 of them `api.get_time`, which is **2 C calls** on any client with
    `GetTimePreciseSec`). Fill is written **twice** (1175-1178 then 1319-1322, the
    2026-10-28 hunter fix); spark decoration is rebuilt every tick (5 C).
  - `set_bar_texts` (`1595-1716`): **O1's cache IS fixed** (reused lookup table, rounded
    string cache, `_st_last_text` gate). Residual: clock re-read at 1620, 3 profile
    chains per tick.
  - `main.lua` range poll (`2793-2828`) is the visibility heartbeat: ≈400-500 client
    calls/s + 2,400-3,200 Lua ops/s at idle with 3 hands, no change-gating (**O6 open**).
    **R1 still live**: `rf_disabled` returns before `set_bar_visibilities` (2794-2797)
    and both calls sit outside the pcall whose re-arm is the last line (2827) → bars
    freeze for the session.
  - `hunter_ui.lua`: anchor hook runs the full visual set at frame rate whenever the
    ranged bar is hidden (`322`, `331-337`, `1824-1866`); 10 guarded sites/tick; the cast
    probe costs 2 C + 8 `is_secret`/frame idle; `update_range_helper` (`1163-1215`) is
    **unthrottled** and re-probes distance + 3 spell ranges per frame with a target.
  - O9 is **partly fixed and partly stale**: the class-hook site string is cached
    (`bars.lua:1284-1289`), and the `{...}`/`unpack` dispatcher path only runs for the
    vendored engine (Forever sends speed-first → takes the cheap branch).
  - **Found a verified correctness defect:** `st.utils.simple_round` (utils.lua:22-24)
    truncates a whole tenth for **8 of 28 weapon speeds** (1.4→"1.3", 2.8→"2.7",
    2.4, 2.3, 1.9, 2.9, 3.3, 3.8). Proven by running the shipped function under lua5.1.
    Used at `bars.lua:1625/1631` for the default left/right texts. The suite pins "2.6"
    (a speed that happens to round correctly) so it is blind; the archived build has the
    same line, so it is inherited, not a regression.
- **Current state:** `bench/bars_perf_audit_2026-11-06.md` written (full census, O/R
  status table, 7 safe mechanical wins + 5 structural, 5 defects, UNVERIFIED list,
  ordered plan). Findings reported to the Lead. 57/0 and 2/0 confirmed before writing.
- **Next step:** (a) the Lead/operator decides on the 9.1 rounding fix first (one line +
  one pin); (b) B1 (O6+R1 decoupling) needs its own lane because it re-cuts the
  `C_Timer.After` pins in `tests/main_init_state.lua:1275-1400` and
  `tests/range_source_state.lua:101/339/532`; (c) still unverified and worth an in-client
  pass: `issecretvalue`/`C_Secrets` presence on 1.60.1, `C_Spell.IsSpellInRange`
  addon-callability there, and which option setters re-run
  `configure_bar_appearances` (gates the spark-decoration win).
- **Not done / not claimed:** no in-client profile (all numbers derived from source at
  60 FPS, stated as such in the report); R2/R3/R4/R5 confirmed present but not re-audited
  in depth (out of scope); no product/test/TOC/git file touched.

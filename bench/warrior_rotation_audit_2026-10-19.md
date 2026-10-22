# Warrior rotation audit vs wowsims sims — 2026-10-19

Desk: warrior-rotation. Read-only; no addon file touched. Per-claim CONFIRMED
(= source said it + citation) or UNCONFIRMED in caps. Our engine =
`classes/warrior.lua` + `warrior_guide.lua`, pinned by
`tests/warrior_state.lua` + `tests/warrior_guide_state.lua`.

## 0. Tooling log

- Code-Mode catalogs enumerated first: `search("firecrawl")` → 10-item
  surface CONFIRMED (agent/status/search/scrape/map/crawl/interact/monitor/
  research families); `search("gh_grep")` → `tools.gh_grep.searchGitHub`
  CONFIRMED.
- gh_grep repo-scoped code search (`Bloodthirst`, `HeroicStrike`,
  repo `wowsims/sod|classic|tbc-new|forever`): **returned nothing** —
  repo filter unproductive on this deployment. Recorded, not retried.
- `firecrawl_search` NOT retried (brief: broken on this deployment).
  `firecrawl_scrape` WORKED on all 12 GitHub tree pages (file listings).
- `webfetch` on `raw.githubusercontent.com` WORKED for all 14 Go/APL files.
- GitHub REST `api.github.com/repos/.../contents/ui` → **403** (rate limit,
  no auth). Recorded; tree scrapes used instead.
- `wowsims/wowsims.github.io` scraped (repo root): **Vite landing template
  only** (78 commits, no sim code, no APLs, no docs). No warrior rotation
  source there. Nothing further taken from it.

## 1. Sim source inventory (all CONFIRMED fetched 2026-10-19)

Era (`wowsims/classic`, our ERA family):
- `ui/warrior/apls/dps_reck.apl.json` + `dps_no_reck.apl.json` (Reck variant,
  same core) — raw fetches.
- `sim/warrior/bloodthirst.go` (BT 23894, cost 30, CD 6s, talent-gated),
  `sim/warrior/whirlwind.go` (WW 1680, cost 25, CD 10s, Berserker-only),
  `sim/warrior/overpower.go` (OP aura 5s + spell CD 5s, Battle-only, rage 5,
  +25% crit/rank Improved OP), `sim/warrior/slam.go` (Slam 11605, cost 15,
  cast 1.5s−0.1s/ImpSlam, `StopMeleeUntil(...,true)` = resets swing).

SoD (`wowsims/sod`, our ERA family + runes):
- `ui/warrior/apls/phase_6_dw.apl.json` + `phase_6_2h.apl.json`
  (latest-phase APLs) — raw fetches.
- `sim/warrior/warrior.go` (stances/runes scaffolding),
  `sim/warrior/heroic_strike_cleave.go` (queue: needs rage ≥ cost, realism
  ICD, auto-drop when rage uncovered), `sim/warrior/execute.go` (E20 or
  Sudden-Death-rune aura; drains ALL rage for +damage/rage),
  `sim/warrior/bloodthirst.go` (23894, 30 rage, 6s).

TBC (`wowsims/tbc-new`, our TBC family):
- `ui/specs/warrior/dps/apls/fury.apl.json` + `arms.apl.json` — raw fetches.
- `sim/warrior/execute.go` (25236, Berserker|Battle, E20-only, drains all
  rage: `925 + 21*extraRage`), `sim/warrior/whirlwind.go` (1680 tag1, cost
  25, CD 10s, Berserker-only, hits 4 + OH when DW).

Forever (`wowsims/forever`, our FOREVER family):
- `ui/specs/warrior/dps/apls/fury.apl.json` + `arms.apl.json` — raw fetches.
- `sim/warrior/dps/dps.go` (no Go rotation — APL-driven),
  `sim/warrior/victory_rush.go` (Victorious-aura-gated Execute-like nuke +
  heal; "Sim never kills a target"),
  `sim/warrior/heroic_strike_cleave.go` (queue needs rage ≥ cost; auto-drop
  when uncovered: "a swing the rage no longer covers drops the queue").

## 2. Era (wowsims/classic) — ours: `is_era_guide`, floor 30, window 2.5s, spam

- M1 MATCH — BT 30 rage / 6s CD. Sim: `classic/sim/warrior/bloodthirst.go`
  (`Cost: 30`, `Duration: time.Second * 6`). Ours: fallback
  `WARRIOR_COMPOSITE_BT_COST = 30` (`classes/warrior.lua:718`), HUD
  `bt = 6` (`:2668`), APL BT `23894 rank 4` ∈ `bt_ids` (`:91-93`).
- M2 MATCH (cost/CD) — WW 25 / 10s. Sim: `classic/sim/warrior/whirlwind.go`.
  Ours: fallback `WARRIOR_COMPOSITE_WW_COST = 25` (`:719`), HUD `ww = 10`
  (`:2669`). Stance gate missing → X6.
- M3 MATCH — OP window 5.0s. Sim: `classic/sim/warrior/overpower.go`
  (`Duration: time.Second * 5`). Ours: `WARRIOR_OVERPOWER_PROC_WINDOW = 5.0`
  (`classes/warrior.lua:53`).
- M4 MATCH — Execute threshold 20. Sim APL `isExecutePhase E20` (both Era
  APLs). Ours: `EXECUTE_PCT_DEFAULT = 20` (`warrior_guide.lua:260`).
- M5 MATCH — HS rank: APL `25286 tag1 rank 8` ∈ `hs_ids` (`:32-35`).
- M6 MATCH — Cleave rank: APL `20569 tag1 rank 5` ∈ `cleave_ids` (`:38-41`).
- M7 MATCH — Slam rank + swing-reset: sim `slam.go` (11605 ∈ `slam_ids`
  `:628`; `StopMeleeUntil(..., true)`). Ours: `slam_cast_safety` classic
  default = clash (`warrior_guide.lua:317-331`). Era APLs never cast Slam
  and our rule 3 is inert without Blood Surge → no Slam prompt on Era,
  correct on both sides.
- M8 MATCH — OP-first on Era: sim has no OP APL line; OP is
  `SpellFlagAPL` so `autocastOtherCooldowns` (APL line 14, before Execute
  line 16) fires it. Ours rule 1 before rule 2
  (`warrior_guide.lua:514-527`). Same order.
- G1 HIGH — **`ww_ids` tracks the wrong spell (OP ranks inside).**
  Sim WW is id `1680` in ALL FOUR sim sources (classic `whirlwind.go`;
  TBC fury APL `1680 tag1`; SoD DW APL `1680`; Forever fury APL `1680
...[truncated 15820 chars]
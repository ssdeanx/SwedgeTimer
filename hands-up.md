# hands-up

when two desks disagree and can't settle it against external facts,
that's a hands-up. it goes to the operator. this is the system working,
not failing.

machine-readable copy: the desk also emits an `escalation/hands-up`
signal into its `.signals/` (per signal-write). the row below is the
human trail.

how it works: a desk raises a hands-up (one row below), states the
disagreement and the evidence each side holds. the operator rules; the
verdict is written back and the row moves to resolved. nothing is argued
to death inside a lane — the trail stays readable.

## open

| # | raised | desks | question | evidence |
|---|--------|-------|----------|----------|
| HU-1 | 2026-10-17 | discovery vs range/weave lane | does banked idea #27 (range helper) duplicate the existing weave_range / range strip? | bench/discover_features.md overlap warning #27 |
| HU-2 | 2026-10-17 | discovery vs hunter lane | does discovered feature #3 (hunter icon group) duplicate H6? | bench/discover_features.md overlap warning #3 |
| HU-3 | 2026-10-17 | discovery vs paladin lane | does discovered feature #5 (paladin CD group) duplicate P2? | bench/discover_features.md overlap warning #5 |
| HU-4 | 2026-10-17 | warrior vs paladin lane | brief_warrior lists the bars_state "glow: combat exit stops the glow (8 vs 7)" failure as warrior-scope. The check is in the PALADIN block and the extra stop traces to classes/paladin.lua:422 `aow_exo_pulse_stop` ← classes/paladin.lua:1428 (paladin `on_combat_exit`) with the P6 pulse never started; warrior.lua appears nowhere in the trace. Who guards the stop (paladin lane) — warrior hard scope cannot reach it? | LCG-stop traceback on /tmp/opencode/mut_warrior (instrumented PixelGlow_Stop, key=AowExoOverlap, bars_state.lua:1578); bench/buildout_warrior_2026-10-17.md §5 |
## resolved

| # | verdict | ruled | rationale |
|---|---------|-------|-----------|
| HU-1 | DEFER | 2026-10-17 (round dispatch) | #27 4-state range helper vs weave_range/range strip — the approved lane plan does not include #27; verify overlap in the options round before any UI addition. Row stays as the record. |
| HU-2 | DEFER | 2026-10-17 (round dispatch) | #3 hunter CD/buff icon group vs H6 badge — H6 badge ships this round inside the hunter lane; the larger icon GROUP is deferred to the options round to avoid duplicate UI. |
| HU-3 | PROCEED | 2026-10-17 (round dispatch) | #5 paladin CD icon group vs P2 JotC bar — different objects (cooldowns vs debuff uptime); both approved in the round plan, both build. |
| HU-4 | RESOLVED-BY-FIX | 2026-10-17 (verification) | Paladin lane made the combat-exit pulse teardown conditional (bench/buildout_paladin_2026-10-17.md); verified in-tree: the glow pin passes, remaining 12 bars_state fails are all count pins. Warrior scope was correctly excluded. |

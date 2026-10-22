# Class Hold Statements — Journal

## 2026-10-20 — Desk opened
- **Purpose:** the class-side half of the HU-8 ruling — each class states its own hold
  explicitly so the practice engine can tell a hold (a decision) from unknown (cannot
  decide). Also carries the class-side pull-clock read into each class's
  `practice_context` builder.
- **Scope:** `classes/paladin.lua`, `classes/rogue.lua`, `classes/shaman.lua`,
  `classes/hunter.lua`, `classes/druid.lua` + each class's own suite(s)
  (`tests/{paladin,rogue,shaman,hunter,druid}_state.lua`, plus a class's guide suite
  only when the pin belongs there). `classes/warrior.lua` is OUT OF SCOPE (a sibling
  lane owns it) — its semantics get filed in the report instead.
- **Engine half (landed, verified):** `bench/shared_engine_bs8_2026-10-20.md`.
  The accessor `H.practice_scenario_step` accepts `{ action = nil, hold = true,
  reason = "<text>" }`; the engine grades a hold as `hold_ok` (no attempt, no points)
  when idle, `illegal_cast` (F, an attempt) when cast, and a step with neither an
  action nor a hold stays unknown (no attempt).
- **Ctx field the engine reads:** `ctx.pull_at` (absolute timestamp) and
  `ctx.pull_in_seconds` (countdown) — per the engine lane's bench artifact §3.4.
- **Next step:** read each class's guide engine for its real hold semantics; state
  only real holds; carry the pull moment into the ctx; pin the three states.

## 2026-10-20 — The class-side hold statements landed
- **Worked on:** the four class files that HAVE a real hold now state it explicitly
  (`{ action = nil, hold = true, reason = <the engine's own text> }`): the paladin
  (the twist RIDE window + the FCFS "nothing is ready"), the rogue (the POOL
  verdict), the shaman (the guide's RIDE / WAIT) and the hunter (the guide's RIDE /
  HOLD). Each class asks its OWN engine whether it held (`out.hold` /
  `out.hold_text`, or the class's own `practice_decision.hold`) — the class never
  re-decides, and an unreadable state stays UNKNOWN.
- **The druid states NO hold** — its guide's hold_text names a spell to PRESS
  (Tiger's Fury / Berserk / Savage Roar / Faerie Fire / Shifting Power / the
  queued Maul), so the step is a decision to cast. Nothing was invented for it;
  the pin now proves the druid's step never carries `hold = true`.
- **Pull clock:** the three classes that publish a ctx builder (paladin, rogue,
  hunter) carry `ctx.pull_at` / `ctx.pull_in_seconds` themselves (read off the
  ADDON OBJECT, the AceAddon table main.lua publishes the clock on). The shaman
  and the druid publish NO ctx builder — the shared engine's fallback builder owns
  their ctx and already carries the same clock (`practice_ui.lua`'s
  `apply_pull_clock`), so no second copy of the ctx shape was written into a class
  file. That fact is pinned (a builder without the pull read fails the pin).
- **Also:** the paladin's `practice_decision.hold` was already there — the step
  simply dropped it; now the step keeps it. The rogue's and the shaman's guides
  already computed the hold and dropped it (`practice_step` returned nil); the
  class asks the guide for the verdict instead of guessing it.
- **Current state:** harness **41 steps, 0 failed**; luacheck **2 warnings / 0
  errors** (the floor: `compat.lua:36`, `main.lua:81` — this lane adds none).
  11 of 11 mutation proofs killed on `/tmp/opencode/hold-mut`.
  Artifact: `bench/class_hold_statements_2026-10-20.md`.
- **Filed for the next lane:** the WARRIOR has a real hold concept (the guide's
  "CANCEL" / "RIDE" / "HOLD"), but `classes/warrior.lua` is out of this lane's
  scope — the semantics are written up in the bench artifact §6 for the lane that
  owns it.
- **Next step:** the orchestrator validates; the warrior lane (or the orchestrator)
  applies the same conversion to `classes/warrior.lua`.

## 2026-10-20 — [signal:done] the class-side hold statements are landed
- The four classes with a real hold state it; the druid states none (it has no
  hold concept). The pull moment reaches every class's ctx. The three states are
  pinned per class. The warrior's semantics are filed for the next lane.
- Signal file: `.signals/2026-10-20T00-40-00Z.json`.

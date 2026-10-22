# class-isolation — Journal

## 2026-10-19 — Desk opened (class-isolation sweep)
- **Purpose:** read-only full-tree sweep proving no class loads another class's functions at runtime; verify rogue F1 closure holds.
- **Scope:** `classes/*.lua`, root `*_guide.lua`, `twist.lua`, `weave.lua`, `nextaction.lua`, `druid_energy.lua`; `compat.lua` reference only. No addon edits, no git, no bench overwrites.
- **Next step:** run the grep sweep per `bench/briefs/brief_class-isolation-sweep_2026-10-19.md`, leave NEW `bench/class_isolation_2026-10-19.md`, append result here, emit done signal.

## 2026-10-19 — Sweep done, bench filed
- **Worked on:** grepped `classes/` + root guides + pure modules for `ST.<OTHERCLASS>`, `st.<other>_guide`, `st.druid_energy`, `st.twist/weave/nextaction`, `st.hunter_window/enemy_swing/weave_range`, `st.hud/nextaction_ui/practice_ui/lust_supported`; read every hit in-tree; checked all 7 TOC tails; checked `compat.lua` both directions.
- **Current state:** 0 runtime-reached cross-class deps. Rogue F1 closure HOLDS (zero `st.druid_energy` in `classes/rogue.lua`; only own `st.rogue_guide`). All other hits are comment-only precedent cites, own-module reads (druid_energy/hunter_window/twist/weave/nextaction/own guide, all TOC-shipped + nil-guarded where archival), or allowed shared infra (api/family/hud/nextaction_ui/lust_supported/practice_ui). Findings filed as NEW `bench/class_isolation_2026-10-19.md` (absent-at-start confirmed).
- **Next step:** orchestrator reconciles; no fix lane needed (every hit carries NO ACTION or ALREADY-CLOSED with rationale). Re-sweep only if a class file gains a new `st.*` read.

## 2026-10-19 — [signal:done] isolation sweep filed
- Bench: NEW `bench/class_isolation_2026-10-19.md` (0 runtime cross-class deps; rogue F1 CLOSED). No fix lane owed.

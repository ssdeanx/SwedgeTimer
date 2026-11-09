# Brief: class-isolation-sweep (2026-10-19)

## Objective
Read-only full-tree sweep: prove no class loads another class's functions at runtime. (Rogue F1 already fixed — verify closure holds, don't re-audit as new.)

## Method
Grep the whole addon tree (excluding `docs/`, `Libs/`) for cross-class references: `ST.<OTHERCLASS>` reads inside a class file that isn't that class, `st.<other>_guide`, `st.druid_energy`, direct calls into another class's functions/table state. For EACH hit: file:line + runtime-reachability verdict (runtime-reached on a live path vs harness-only vs comment/dead) + severity (a wrong-class nil-index on a hot path is top priority) + fix direction (vendor the pure logic into the owning class; never cross-call; shared root pure modules like twist.lua/weave.lua are allowed only if they are class-neutral and loaded for all families that use them).

## Scope
READ-ONLY except one NEW bench file + own desk. Subject files: `classes/*.lua`, root `*_guide.lua`, `twist.lua`, `weave.lua`, `nextaction.lua`, `druid_energy.lua`, `compat.lua` (reference only — the single cross-client layer is SUPPOSED to be called by all). Output: NEW `bench/class_isolation_2026-10-19.md` (confirm absent at lane start; supersede-with-pointer if present). No code edits. No git.

## Context (read first)
`desks/journal.md`, `bench/rogue_client_isolation_2026-10-19.md` (rogue already swept: F1 fixed by vendoring EMA into rogue_guide; F3 comment-only), `bench/lessons.md`.

## Rules
Every finding: file:line + evidence (proven offline via read) + verdict. UNCONFIRMED where in-client. Extend prior audits, never re-derive.

## Mechanics (skills — CALL these tools, in order)
bench-read (journals before artifacts) → desk-open `desks/class-isolation/` (resume if live) → work → desk-journal append → signal-write done JSON + journal marker.

## Validation owner
Orchestrator reconciles violations into fix lanes; every violation actionable (file:line + fix direction).

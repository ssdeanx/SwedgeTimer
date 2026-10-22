# sod-detect — Journal

## 2026-10-19 — Desk opened
- **Purpose:** SoD-vs-Era runtime detection (read-only investigation).
- **Scope:** compat.lua, tests/smoke.lua, bench/verify_bank.md, wow-ui-source branch names.
- **Next step:** run the ERA+rune-knowledge probe finding; write bench/sod_detect_2026-10-19.md.

## 2026-10-19 — [signal:done] SoD detection finding landed
- **Worked on:** family-detection read (compat.lua:49-113), smoke profiles, verify_bank SoD items, branch-name check (no sod branch), per-class rune probes (hunter/paladin/druid/shaman/warrior/rogue).
- **Current state:** bench/sod_detect_2026-10-19.md on disk: no offline discriminator; ONE mechanism = per-class ERA + api.is_spell_known rune probe (MW via aura latch); UNCONFIRMED items capped.
- **Next step:** orchestrator owns in-client validation (per-class id checks + optional C_Engraving/build-string probes).

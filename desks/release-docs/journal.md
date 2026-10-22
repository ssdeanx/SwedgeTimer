# release-docs — Journal

## 2026-10-19 — Desk opened
- **Purpose:** per OPERATOR ORDER (no version bump): retitle CHANGELOG `[Unreleased]` → `[2.1.1]`; verify-only all 8 version fields; coherence scan for dangling promises.
- **Scope:** CHANGELOG.md header + coherence lines only. Version fields VERIFY ONLY. Everything else OUT.
- **Next step:** execute bench/briefs/brief_release-docs_2026-10-19.md.

## 2026-10-19 — Release-docs pass executed (done)
- **Header:** `## [Unreleased]` → `## [2.1.1]` (CHANGELOG.md:3). CRLF preserved; zero `Unreleased` hits remain.
- **Version verify (read-only, no edits):** all 7 TOCs line 5 read `## Version: "2.1.1"` (base + Vanilla/TBC/Wrath/Mainline/Cata/Mists) and main.lua:5 reads `local version = "2.1.1"` — 8/8 at 2.1.1.
- **Coherence scan (2.1.1 section):** one stale deferral found + fixed — the enterprise-grade line said "hidden-slot row reflow deferred past combat lockdown" but the hud-reflow lane closed it (reflow on hidden-flip outside combat, deferred only under lockdown); added pointer to bench/buildout_hud-reflow_2026-10-19.md.
- **Checked, left untouched (disclosed, not dangling):** `hunter_multi_target` toggle-only + "(future)" copy (option_tables.lua:3323 confirms the marker); paladin/warrior Anniversary string-fallback `/dump` owner action (stated as unsettled); UNCONFIRMED in-client flags throughout.
- **Note (no code lane needed):** rogue-auditfixes (F1/F2/F4/F5/F6, ses_eabfd039dffeFpqsx5K1Kwl185) have no CHANGELOG lines; adding entries is orchestrator's call (scope here was header + coherence only).
- **Validation owner:** orchestrator.

## 2026-10-19 — Post-section rogue append (done)
- **CHANGELOG [2.1.1] Rogue section:** appended one "Post-section landings" bullet (5 items, one line each with bench/desk pointers). Header stays `[2.1.1]`; no version-field edits. CRLF preserved.
- **Verified in-tree before writing:** `ST.ROGUE.get_rotation_key` (classes/rogue.lua:1275, hunter-shape contract :1234); ROGUE in `PROVIDER_CLASSES` (diag.lua:51); red defaults (`show_rogue_ss_window` true + `rogue_ss_color` {255,64,48} red, config_presets.lua:603-604, owner order classes/rogue.lua:20,46-47); warrior counter (`warrior_unmatched_payloads` + `WARRIOR_PAYLOAD_NOTICE_AT`, classes/warrior.lua:1313-1316); F1 NaN-safe funnel (rogue_guide.lua:182), F2 count probe chain (compat.lua:1061-1069), F4 POOL_BANDS pins (tests/rogue_guide_state.lua:82-86), F3 residual per central reconcile.
- **Validation owner:** orchestrator.

# paladin-followups — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Build the filed paladin follow-ups engine-side (stopattack discipline, prepull guidance, SoD seal-maintenance, SoD variants per wrath_sod §4, cast-time probe, mana-threshold groundwork, hard-wait UI groundwork); rank-1 advice only on a verified live reader.
- **Scope:** ONLY classes/paladin.lua, twist.lua, nextaction.lua, tests/paladin_state.lua, tests/twist_state.lua, tests/nextaction_state.lua, compat.lua (cast-time probe only if verified missing — check wrappers first).
- **Next step:** Implement engine additions nil-safe/no-default-visible-change, pin with tests, harness + luacheck + mutations green, file the out-of-scope remainder.

## 2026-10-19 — Follow-ups built engine-side, remainder filed
- **Worked on:** nextaction.lua (stopattack/prepull/rank-1/hard-wait advisories, 2 constants, SoD seal-maintenance rule, RETAIL + FCFS inert paths); classes/paladin.lua (HoW cast-time probe ms to s cached per rank, mana-cap read path, rank-1 book read, strict_sequence rune gate, display mapping for 5 advisories); tests (+49 nextaction incl. boundary/NaN/RETAIL/mode pins, +21 paladin incl. probe units + mapping threading).
- **Current state:** nextaction 526 + paladin 316 + twist 84 PASS; full harness 37/0; luacheck 2/0 floor (compat:36 pre-existing + one sibling-owned; my files 0); 10/10 mutations killed on /tmp/opencode/palfu (copy restored clean). twist.lua + compat.lua untouched with reason (nothing to wire; probe verified present at compat.lua:160-176). Bench report: bench/paladin_followups_2026-10-19.md (built table + SoD variant verdicts + 9 filed needs with file:line).
- **Next step:** Orchestrator validates; UI/options/main lanes own the 9 filed needs; in-client test session per standing rules.

## 2026-10-19 — [signal:done] Paladin follow-ups built engine-side, remainder filed
- nextaction 526 + paladin 316 + twist 84 green; harness 37/0; luacheck 2/0; 10/10 muts killed; bench report on the bench. Validation owner: orchestrator.

## 2026-10-19 — Hard-wait render live, rank-1 slot re-filed
- **Worked on:** nextaction_ui.lua display_active only: out.hard_wait == true paints WAIT (optional labels.wait, default "WAIT") inside the existing unknown/hold/hold_enabled gates, no db key; header contract +2 lines. Provider (classes/paladin.lua) + engine (nextaction.lua) untouched — threading already live (mapping 3038-3039, engine 849). tests/paladin_state.lua +5 pins: archived hold_text on hard wait (RIDE) + plain hold (HOLD), 2 render source pins, rank-1 no-slot filed pin.
- **Current state:** paladin 321 + nextaction 526 + guide_contract 853 green; harness 38/0; luacheck 2/0 floor (compat + main pre-existing, touched files 0); 5/5 mutations killed on /tmp/opencode/hw_lane (copy restored clean, /tmp cleaned).
- **Next step:** Orchestrator validates; rank-1 render + option + SoD seal-maintenance slot stay with UI/options lanes. Rank-1 filed: classes/paladin.lua:2941 (slots, no rank1 key — same id 20375 as soc/twist, distinct render needs UI decision + opt-in, both out of scope, no inert toggles).

## 2026-10-19 — Stopattack / prepull / mana-threshold UI render live, rank-1 stays filed
- **Worked on:** classes/paladin.lua display mapping only (out.mana_low derived from threshold+mana+riding, no rule change; advisory + strictSequence comments filed→live); nextaction_ui.lua render only (display_active STOP/PULL/OOM/WAIT chain, STOP+PULL force-show, header + labels docs; display_idle inputs-based PULL cue vs engine lead with soc light); tests/paladin_state.lua +18 pins (6 mana mapping incl. threshold boundary, force-show + branch-order + idle + rank1-absent src pins).
- **Current state:** paladin 439 + nextaction 585 + guide_contract 991 green; luacheck 0/0 touched files (tree floor 2/0 held); 6/6 mutations killed on /tmp/opencode/palaui copies (STOP text, force-show, branch order, riding gate, strict-below boundary, OOM text; copy restored pristine, /tmp cleaned). Full harness 38 steps: my 4 suites PASS; hunter_state/shaman_guide_state/hud_templates_state RED = sibling crossfire (hunter traps, shaman weave, rogue options — none reference paladin), orchestrator to reconcile. Rank-1 still filed, absence pinned (slot table + UI).
- **Next step:** Orchestrator validates; pull-timer source (main lane), options widgets (O lane: twist_mana_threshold default), family seal choice + macro (filed) stay out.

## 2026-10-19 — [signal:done] Paladin stopattack/prepull/mana UI render live, rank-1 filed
- STOP/PULL/OOM renders + idle prepull + mana_low mapping; paladin 439 green; luacheck 0/0 touched; 6/6 muts killed; harness crossfire sibling-owned (hunter/shaman/rogue-options). Validation owner: orchestrator.

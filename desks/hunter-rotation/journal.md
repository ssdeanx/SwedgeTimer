# Hunter Rotation — Journal

## 2026-10-19 — Desk opened
- **Purpose:** hunter rotation vs wowsims sims audit (read-only).
- **Scope:** classes/hunter.lua, hunter_guide.lua, tests/hunter_state.lua, tests/hunter_guide_state.lua vs sod/forever/classic/tbc-new/wotlk sim sources.
- **Next step:** audit written to bench/hunter_rotation_audit_2026-10-19.md; emit done signal.

## 2026-10-19 — [signal:done] hunter rotation audit complete
- **Worked on:** read-only compare of hunter guide/engine vs wowsims sod/forever/classic/tbc-new/wotlk sim code + APLs.
- **Current state:** bench/hunter_rotation_audit_2026-10-19.md written (per-client MATCH/GAP/CONFLICT with file:line + sim sources). Top gaps: Wrath LnL + Serpent, Forever sim-confirmed ids (client check still owed), TBC Arcane, SoD Serpent.
- **Next step:** orchestrator validates; in-client id confirmations owed before any wiring.

## 2026-10-19 — Gap closure (engine side, nil-safe dormant) [signal:done]
- **Worked on:** closed/filed all 9 ranked audit findings inside scope (hunter_guide.lua + classes/hunter.lua + tests/hunter_guide_state.lua; hunter_state.lua untouched, no pins owed there). Engine: W-LnL free Explosive/Arcane arm (Wrath, ignore-CD, below execute), SoD-LnL free Aimed/Multi arms (ERA, ignore-CD, clip-gated, below Chimera), Serpent guard on W2/5b (known-down withholds naked Chimera; unknown=allow), 5c TBC Arcane arm dormant behind TBC_ARCANE_ENABLED=false (base set full 6/6), rule-2b Sniper-buff bypass (Forever MM 42-45yd). Gather writes all four new inputs nil every call (no aura/debuff/buff source wired; unknown-hides, zero new client queries, no default-visible change). Tests: 1048->1115 checks (+67 pins: arms, guards, gates, plug flip, bypass, gather nil + stale-table).
- **Current state:** scope green: hunter_guide_state 1115/1115, hunter_state 510/510, luacheck 0/0 on all 4 scope files, endings preserved (CRLF x2, LF x2). 5/5 mutations on /tmp/opencode copies kill (LnL-multi assign drop, serpent-guard weaken x2 pins, 2b-bypass strip, gather lnl-leak x8 pins, 5c action swap x2 pins; copies removed). Full harness NOT green: rogue/nextaction/druid/shaman/wiring_check + bars_state fail inside rogue.lua/paladin-era files edited 09:47-09:50 by concurrent lanes (crossfire, none load hunter files); rotationtext/hud/diag/main_init pass. luacheck tree-wide fluctuates with the same crossfire.
- **Next step:** orchestrator owns validation + reconcile (crossfire triage). Follow-ups filed (need out-of-scope files, no engine guess made): compat/target-aura scan for LnL proc (56344/415413 sim-confirmed) + Serpent debuff + Sniper buff; TBC arcane slot + options wiring (contract full); Forever Sniper/Hawk ids (1310687/1310785/1310786, 1293241/1293525/1293526/1293527) + hawk-count source + HHA sequence (stateless engine won't sequence); TBC melee-weave/move cues + trap-weave timing + ISS/Readiness display (HUD/bars); mana/Viper/prepull/mark/aspect/Sniper-Training (compat/mana/options); H2 lust-suppression sim query (UNCONFIRMED); TBC Steady-34120 downrank + Wrath Explosive 60053/60052 rank coverage (no id change here).

## 2026-10-19 — Hunter open items resolved [signal:done]
- **Worked on:** read-only resolution of the 5 filed follow-ups vs fresh-fetched sim sources (wotlk talents.go + steady_shot.go, tbc-new + sod p7 + forever default APLs, sod runes.go, forever summon_hawk.go + spell_data_auto_gen.go). Wrote bench/hunter_open_2026-10-19.md: traps/ISS/Readiness → badges not arms; mana/Viper/prepull → cut from guide (HUD badge + practice shape); hawk-count → cut until probe (single blocker); Forever ids → SIM-CONFIRMED, wire only after 1.60.x GetSpellInfo; H2 → no APL lust-branch in any of 3 APLs, recommend CUT (orchestrator decides).
- **Current state:** 5/5 verdicts delivered with per-item sim cites + file:line. No addon files touched.
- **Next step:** orchestrator validates; in-client probe session owed (Forever ids + hawk-count source + H2 keep/cut re-pin).

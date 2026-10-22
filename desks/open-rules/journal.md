# open-rules — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Resolve three open rule questions with sim/WA evidence: H6 lockout/wait rule, fight-remaining-time source, Victory Rush handling.
- **Scope:** read-only: bench/warrior_rotation_audit_2026-10-19.md, bench/paladin_rotation_audit_2026-10-19.md, bench/rogue_rotation_audit_2026-10-19.md, bench/verify_bank.md, cited class files, wowsims repos (sod/forever/classic/tbc-new) via webfetch. No addon edits, no git, no bench overwrites.
- **Next step:** write NEW bench/open_rules_2026-10-19.md with a verdict per item + evidence; emit done signal.

## 2026-10-19 — Verdicts written [signal:done]
- **Worked on:** read all three rotation audits + verify_bank + rogue-rotfix/warrior-rotfix journals; read rogue_guide.lua (EA verdicts, rule order, TTD EMA), warrior_guide.lua (rule 2/B victory_rush bypass), classes/warrior.lua (VR probe 2500-2518, execute-slot reuse 2180-2181), classes/paladin.lua (fight_remaining_pct nil-feed 2770-2773), nextaction.lua (SOD_EXECUTE_FIGHT_PCT=10 :361, burn rule :877-892). Fetched 6 raw sim files: tbc-new swords.apl.json, forever default.apl.json (rogue), forever victory_rush.go, forever fury/arms APLs, classic combat_sinister_strike.apl.json, sod P5_Saber.apl.json + retribution_paladin p8-twist.apl.json.
- **Current state:** NEW bench/open_rules_2026-10-19.md on disk. Verdicts: H6 BUILD (APL-literal TBC 15s-minimum + waitUntil pool-for-EA + Forever finisher lockout, all behind ea_duty, nil-safe); fight-remaining CUT (sim encounter clock has no WoW API source; TTD/HP% approximations already cover single-target; paladin stub stays nil-fed); Victory Rush HOLD DORMANT (sim models but never casts — "Sim never kills a target"; bypass is nil-safe + slot-free, needs Forever in-client id/aura confirm before any wiring).
- **Next step:** orchestrator validation; H6 build lane owns APL-literal design + tests; VR + fight-clock confirmations are in-client checklist items.

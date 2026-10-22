# Desk: five-class-gaps

## 2026-10-19 — writer lane open

- Worked on: bench-read (journal, hunter+proctor audits, rogue_erroraudit H-closure,
  readiness §§1/4, lessons, hands-up); gap comparison across the five class modules.
- Current state: every checklist cell inspected. WIRED: HUD slots+provider,
  guide+gather, get_rotation_key (paladin's lives in rotationtext.lua:222, pinned),
  on_bar_update order (hunter hud-first is independent frames, no behavior),
  on_combat_exit record preservation (G4, all five), spell-id tables + R1 fallback
  (paladin+warrior CLEU consumers both have it), practice scenarios (all classes),
  diag PROVIDER_CLASSES (all five + rogue), designmode (shared descriptors, no
  per-class gap), spellcast self-guards (shaman:768, warrior:1239; rest dispatched
  behind init guards). ONE fixable gap found: warrior CLEU lacks the paladin M3
  unmatched-payload counter (classes/paladin.lua:648-657); porting it now.
- Next step: warrior M3 edit + pins + harness + mutations, then follow-ups + signal.

## 2026-10-19 — writer lane done

- Worked on: warrior M3 port (classes/warrior.lua:53-58 constant,
  :1303-1319 counter+notice in on_combat_log_unfiltered SPELL_MISSED);
  tests/warrior_state.lua §18b (15 checks); notices-guard hardening in
  warrior + paladin M3 pin sections (test-only, error-to-FAIL).
- Current state: harness 37/0, luacheck 2/0 floor held. Mutations on
  /tmp/opencode copies: M1 strip-block 8 FAIL, M2 threshold-999 3 FAIL
  (counter pins pass), M3 inverted-shape 8 FAIL — all exit 1, no errors.
  CRLF (warrior.lua) / LF (tests) preserved. No config/options/TOC/docs
  touched. CONDITIONAL diag/practice not triggered (no class-scoped gaps).
- Next step: orchestrator reconcile (per-class dispositions + follow-ups
  in the done signal).

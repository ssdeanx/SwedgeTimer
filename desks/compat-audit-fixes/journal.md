# compat-audit-fixes — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Fix the 3 compat bugs from bench/perclient_api_audit_2026-10-19.md (G-gap list): (1) C_Spell.IsSpellKnown* dead probes, (2) cleu_supported shim gate, (3) C_ShapeshiftForm dead probe.
- **Scope:** compat.lua, tests/secret_guard_state.lua, tests/smoke.lua (compat pins only). No class/guide/options/config/bars/hud/practice/main/diag/guide_contract/run.sh/TOC/docs edits; no git.
- **Next step:** Apply the three compat.lua fixes + pins, then harness + luacheck + mutation proofs on /tmp/opencode copies.

## 2026-10-19 — All three compat bugs fixed + pinned
- **Worked on:** (1) Removed dead `C_Spell.IsSpellKnown*` probes (verified absent on all 5 ref branches via `git grep`; live namespace is `C_SpellBook`) — chain is now classic global first, then `C_SpellBook.IsSpellKnown` + new `IsSpellKnownOrInSpellBook` sibling fallback; comment cites SpellBookDocumentation.lua both names. (2) `st.cleu_supported` now `and not st.is_mainline` — Deprecated_CombatLog.lua shim (loadDeprecationFallbacks-gated, all 5 branches incl. live) can define the global on Forever/Retail with no classic log behind it; comment cites the shim file. (3) Removed dead `C_ShapeshiftForm` branch (verified absent all 5 branches) — bare `GetShapeshiftForm` global stays first (allowlisted in RestrictedEnvironment.lua on era/anniversary/titan = Era fallback confirmed, no in-client fall-to-0), else 0; comment documents.
- **Pins:** smoke R3 +2 shim cases (Forever/Retail w/ shim global stay false), +3 shapeshift cases (bare-global priority, lone-namespace ignored→0, retail→0); secret_guard R7 +namespace pin (fictional C_Spell knowledge ignored), +sibling pins (OrInSpellBook answers). Builder gained `c_spell_known` / `c_spellbook_in_book` opts only.
- **Current state:** smoke 188/0, secret_guard 340/0; full harness 38 steps 3 failed = hunter_state (TRAPS crossfire: §20 test refs H.TRAPS absent from classes/hunter.lua, parallel lane mid-write — mtimes 13:56/13:57 EDT confirm), guide_contract + hud_state (red at baseline too, parallel-lane crossfire). luacheck floor 2/0 held (my files: 1 pre-existing `addon_name` warning, untouched). 5/5 mutations kill on /tmp/opencode copies (copy removed). No other files touched; LF endings preserved.
- **Next step:** Orchestrator reconciles the 3 out-of-scope reds (all parallel-lane crossfire). No follow-ups from this desk.
- **[signal:done]** all three fixed + pinned; validation green on scope.

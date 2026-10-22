# class-stubs-fix — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Fix hunter-resweep HIGH (ses_eaaf2f3b7ffeuygfA6RMet8AyF): add ST.MONK / ST.DEMONHUNTER / ST.EVOKER stubs so Retail logins for those classes don't nil-index at the dispatch sites.
- **Scope:** main.lua stub block only (3 lines, token order) + stub-presence/dispatch-no-throw pins in tests/main_init_state.lua. No class_hands/db changes (AceDB ['**'] + get_class_hands {} fallback verified).
- **Next step:** Apply stub edit (CRLF-safe), append section 13 pins, run harness + luacheck + mutation proofs on /tmp/opencode copies.

## 2026-10-19 — Fix landed, harness green
- **Worked on:** main.lua stub block +3 lines (ST.DEMONHUNTER/EVOKER/MONK, token order, CRLF verified); tests/main_init_state.lua section 13 (13 presence pins + 13 classes x 25 login/aura/cast/rage/swing dispatches no-throw + wired-hook deltas). No class_hands/db changes (AceDB ['**'] at config.lua:56 + get_class_hands {} fallback verified).
- **Current state:** Harness 38/0, luacheck 2/0 floor held. Mutation proofs kill: dropping ST.MONK or ST.DEMONHUNTER on /tmp/opencode copies fails 14/688 at the exact reported sites (post_init guard, aura/cast-queue/lifecycle wrappers, spellcast + rage forwarders). Guarded-pattern sites (cooldown/autorepeat/talent/combat) correctly do not fail. No other files touched; no git.
- **Next step:** Orchestrator validates (hunter re-sweep re-verify + harness rerun on landing).

## 2026-10-19 — [signal:done] class-stubs fix complete
- Harness 38/0 + luacheck 2/0 + 2/2 mutation kills; scopes kept (main.lua stub block, main_init_state pins only).

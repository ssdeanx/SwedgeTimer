# rogue-ema — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Fix rogue isolation F1 HIGH — vendor druid D4 EMA math into rogue-owned space, remove st.druid_energy cross-class read.
- **Scope:** ONLY classes/rogue.lua, rogue_guide.lua, tests/rogue_state.lua, tests/rogue_guide_state.lua. Everything else OUT.
- **Next step:** Verify cited lines in-lane, implement pure helper + consume, pin equivalence + absence, validate harness/luacheck/mutations.

## 2026-10-19 — F1 fixed, verified
- **Worked on:** Vendored druid D4 EMA into rogue-owned space: rogue_guide.lua gains TTD_EMA_ALPHA/TTD_SAMPLE_SECONDS (0.25/0.25) + update_hp_velocity/get_time_to_die (byte-identical maths); classes/rogue.lua get_time_to_die consumes st.rogue_guide (rg) instead of st.druid_energy; reworded 3 st.druid_energy comment cites; tests/rogue_state.lua drops druid_energy.lua from sandbox, presence pin → F1 absence pins (st.druid_energy + ST.DRUID), +13 equivalence vectors; tests/rogue_guide_state.lua +near helper +26-check EMA section. Scope held: only the 4 allowed files.
- **Current state:** rogue_state 367/0, rogue_guide_state 251/0; full harness 37 steps 1 failed = bars_state paladin/warrior/druid count pins (sibling lanes' half-landed edits, no ROGUE failure, out of scope); luacheck 2/0 floor held (0/0 on the 4 touched files); mutations on /tmp/opencode copies all killed (MUT1 reintroduced read → F1 pin fails; MUT2a raw-velocity → 3 pure fails; MUT2b nil-divide → 4 behavioral + 3 pure fails); grep proof: zero st.druid_energy/ST.DRUID in classes/rogue.lua + rogue_guide.lua. No is_mainline gates added; nil-safe/unknown-hide behavior unchanged.
- **Next step:** Orchestrator owns validation + in-client test session; no follow-up owed by this desk. UNCONFIRMED: none new (TTD tuning ledger items stay with the owner).

## 2026-10-19 — [signal:done] F1 rogue EMA vendored, all proofs green
- rogue_state 367/0, rogue_guide_state 251/0; harness 37/1 (sibling-lane bars pins only); luacheck 2/0 floor; 3/3 mutations killed; zero cross-class refs in shipped rogue files.

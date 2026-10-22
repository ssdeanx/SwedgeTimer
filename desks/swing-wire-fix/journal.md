# swing-wire-fix — Journal

## 2026-10-22 — Desk opened
- **Purpose:** HU-25 real-lib harness (B1, red first) + D8 deadline rewire (B2) per `bench/briefs/brief_swing-wire-fix_2026-10-22.md`.
- **Scope:** NEW `tests/real_wire_state.lua` + narrow `main.lua` regions only (deadline :393-411, INFO callback :382-386, `register_timer_callbacks` :770-777 + one rewire guard). HU-27 overlap: touch nothing else in `main.lua`.
- **Next step:** build harness, record red on pre-fix tree, then fix.

## 2026-10-22 — Harness built, red recorded (pre-fix tree, unmodified)
- **Worked on:** wrote `tests/real_wire_state.lua` (real LibStub + shipped v7 + real vendored lib + real main.lua path; stubbed Ace/LRC/LLM/LGC/frames only). Legs: Era happy, Anniversary(level=1) happy, D8 negative, Anniversary-nil D2.
- **Current state:** RED recorded (see report): happy legs green, D8 leg red (N FAILs), D2 expected-fail pending HU-29. Suite output pasted in builder report.
- **Next step:** B2 rewire fix in main.lua, then green run + run.sh + mutations.

## 2026-10-22 — Rewire landed, green except orchestrator-owned items [signal:done]
- **Worked on:** B2 fix (stash REAL_STL/REAL_SWING_ENGINE upvalues; late-INFO re-point + guarded re-register + re-seed without frame re-creation; double-reg guard on register_timer_callbacks). Two mid-course corrections: (1) stock-Lua xpcall drops v7 callback args — suite carries a forwarding shim (in-tree proof: 3 shipped Ace libs rely on it); (2) a recovery-Print draft broke main_init_state s1b, so the rewire is chat-quiet — truthfulness rides on ST.swing_engine + deadline=fired diag.
- **Current state:** suite 112 checks / 0 failures / 1 expected-fail (D2-nil, HU-29); run.sh 46 steps 1 failed (only the toc_check run.sh-registration pin the orchestrator closes via FILED); luacheck 2/0 floor held; 2/2 mutations caught (14 + 16 fails); main.lua CRLF intact, local max far under 190.
- **Next step:** proctor verification. FILED: run.sh line for the new suite (see done signal / builder report).

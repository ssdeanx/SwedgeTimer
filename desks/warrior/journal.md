# warrior — Journal

## 2026-10-17 — Desk opened
- **Purpose:** W1/W2 (rage gate before BT/WW ordering) /W3/W7 + HS tint + Shield Block bar + Battle Shout.
- **Scope:** classes/warrior.lua only.
- **Next step:** wait for dispatch brief in bench/briefs/; corrections from bench/verify_bank.md apply (W2 rage gate, W7 degrade confirmed).

## 2026-10-17 — Build-out round 1 done, finisher pass (offline-verified)
- **Worked on:** finished the partial work left by the rate-limited first attempt. Kept the W1 bank cue, W2 composite rage gate, W3 rampage tiers, W7 probe fallback, Battle Shout badge and the pre-existing trackers; fixed the one code bug — `get_hud_state`'s `op` branch armed the usable-probe fallback on an armed-but-elapsed proc stamp, so the OP glow never stopped (hud_state pin). New rule: live window glows + skips probe; elapsed stamp = window's verdict (no glow, no probe); probe only for a never-armed (nil) stamp. Test fixes: the W3 "elapsed" row used `0.0` vs the "zero expiry" row's `0` (identical Lua numbers — replaced with a real elapsed expiry); the BS toggle-off row never turned the toggle off; added mirrored W7 lifecycle pins (618 → 620 checks).
- **Current state:** `tests/warrior_state.lua` PASS 620 checks; `tests/hud_state.lua` PASS 401 checks (no hud_state edit); luacheck 0 errors (2 pre-existing warrior.lua formatting warnings). Mutation proofs on `/tmp/opencode/mut_warrior` byte-faithful copy: rage-gate threshold break → 10 FAILs; glow-fix revert → hud_state 1 + warrior_state 2 FAILs; both restored green. bars_state counts reported, not reconciled: warrior +1 texture (bank edge) / +2 fontstrings (BANK label, BS badge).
- **Escalated:** bars_state "glow: combat exit stops the glow (8 vs 7)" is in the PALADIN block — traceback shows `paladin.lua:422 aow_exo_pulse_stop` ← `paladin.lua:1428` on combat exit with the pulse never started (P6 lifecycle; paladin lane's). Warrior scope cannot reach it → HU-4 row + escalation signal.
- **Next step:** in-client verification of the glow lifecycle, W1 band/floor, W2 prompts, W3 tiers and BS badge; options pass wires `show_warrior_bank_cue` / `show_warrior_battle_shout_badge` (both nil = OFF); bars_state count wave reconciles the reported deltas.


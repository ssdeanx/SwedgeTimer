# Brief: shaman-weave — MW weave at 2-3 stacks + spell markers + Flurry ICD sync (round 2)
Date: 2026-10-17. Operator directive, verbatim intent carried below.

## Operator's spec (binding)
- "shaman dont have to wait until 5 stacks for mw, that for basic players. if u combine it with our shaman lb weaving, u can actually do it at 2-3 if u cast it at correct time and dont clip your mh weapon."
- "it should also update where each spell is relative to swing bar so u know where you have to cast"
- "after each swing, lb, cl and rest should update and readjust where they need to be casted by"
- "for dw shamans they want to keep both mh/oh in sync so they dont consume extra flurry stacks bcuz flurry has .5 sec icd aka internal cooldown"
- "its super dps if u can do 2-3 stack lb weaves but if u clip your weapon at all then it is a dps loss"
- Screenshots (3, described): swing bar with OH/MH labels and white sweep; a bracket above the bar labeled "Spells start cast range zone"; blue spell icons (LB, CL) positioned inside that zone ahead of the MH marker; cast-time numbers (2.4 / 1.9) shown; one frame shows the clipping case where a cast extends past the MH swing. Operator will send an example link later — structure the visuals so a follow-up can refine them.

## Read first
desks/shaman/journal.md · desks/journal.md · bench/buildout_shaman_2026-10-17.md (S2/S3/S4/S5 just landed — this addendum REFINES S4's trigger; the LvB rune/talent gate stays) · bench/verify_bank.md (S rows) · AGENTS.md (weave section) · bench/lessons.md · CAIRN.md

## Scope — writable files (hard boundary)
weave.lua, classes/shaman.lua, tests/weave_state.lua, tests/shaman_state.lua. NOTHING else. Do NOT touch tests/bars_state.lua (counts are reconciled in the final wave — report any new bar texture/frame counts in your bench report instead). Draw on the bar only via the existing class hook.

## Task
1. **Spell-position markers**: for each weave spell (LB, CL; LvB when known), compute WHERE on the swing timeline its cast must START so it completes just before the MH swing — the safe cast-start window ("spells start cast range zone"). Render spell icons positioned in that zone on/above the bar; they advance with the swing. Show cast time. The clip case must be visually distinct (operator: clip = dps loss).
2. **2-3 stack MW weave**: prompt LB/CL when MW ≥ 2 AND the cast fits the safe window (no MH clip); 5-stack stays the safe fallback; NEVER prompt a clip. This is the operator's core request — the 2-3 stack weave is the "super dps" path.
3. **Dynamic re-adjust**: after every swing / LB / CL / any weave event, recompute and redraw marker positions + the safe zone.
4. **DW Flurry sync + ICD awareness**: track Flurry stacks and its 0.5s ICD; MH/OH sync indicator/warning so desync doesn't burn extra Flurry stacks; model the ICD where it affects timing. Structure the ICD knowledge so more ICDs can join later (operator: "figuring out how to take advantage of and knowing icd's").
5. weave.lua stays WoW-free (pure math); classes/shaman.lua renders/drives. Never gate on st.is_mainline alone — swing activity decides. All toggles nil-safe, default OFF; document defaults for the options pass.

## Validation
bash tests/run.sh — your suites green (bars_state/hud_state are the final reconcile wave; leave them). luacheck 0 errors. Mutation proofs on /tmp/opencode copy (clip guard; 2-3 stack gate; Flurry ICD). Extend weave_state + shaman_state — never weaken.

## Deliverables
Code · desks/shaman/journal.md entry · signal JSON in desks/shaman/.signals/ · bench/buildout_shaman-weave_2026-10-17.md (marker math spec, screenshots-to-model mapping, option defaults, bar-count deltas for the reconcile wave, UNCONFIRMED list). Final reply ≤6 lines. NEVER run git.

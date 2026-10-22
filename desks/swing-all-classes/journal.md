# swing-all-classes — Journal

## 2026-10-22 — Desk opened
- **Purpose:** prove the other five classes (rogue, paladin, shaman, warrior, druid) do not have the hunter id-only disease, fix every instance with id-primary/name-secondary.
- **Scope:** classes/rogue.lua, classes/paladin.lua, classes/shaman.lua, classes/warrior.lua, classes/druid.lua (+ rogue_guide.lua / nextaction.lua ONLY if class guide input needs it); legs in each owning suite. Off-limits: hunter, hunter_ui, main, bars, compat, run.sh, Libs, TOCs, versions, options.
- **Next step:** extract hunter pattern, grep-audit five classes, cross-client truth via git show, fix + legs + focused validation.

## 2026-10-22 — id-primary/name-secondary sweep done (all five classes)
- **Worked on:** audited rogue/paladin/shaman/warrior/druid for the hunter disease (numeric-id-only match on Anniversary-nameable payloads). Fixed 7 instances: druid is_maul_token (SUCCEEDED/FAILED_QUIET/INTERRUPTED, was family-gated) + FF aura read (was id-only); warrior HS/Cleave SUCCEEDED+FAILED_QUIET (were id-only, ignored cast_guid; split localized sets per ability); paladin Exorcism SUCCEEDED (was id-only); rogue find_unit_aura + utility_aura_present + update_lust_state (were family-gated/id-only). Shaman already both-shapes (lookup_weave_family + totem matchers) — clean, proof legs only. rogue_guide.lua + nextaction.lua: zero spell_id/cast_guid/GetSpellInfo matches — pure engines, no change. Paladin aura_matches (id universal + name on TBC) and query shapes (spell_query/get_spell_query/rogue_query) left as the sanctioned query discipline — matching only was in scope.
- **Current state:** 4 class files + 5 owning suites changed, nothing else (hunter/main/bars/compat/run.sh/Libs/TOCs untouched). Focused suites green: druid 1606, warrior 2070, paladin 1241, rogue 1131, shaman 1073; companions green (rogue/druid/shaman/warrior guide, nextaction, twist, weave, hunter ×2, bars, hud, contract, main_init, wiring). luacheck full tree 2/0 (pre-existing floor). 8 red-first mutations on /tmp copies (all removed): each kills exactly the new name legs, id legs stay green.
- **Next step:** orchestrator runs full run.sh + decides on residual filings (paladin AoW/SoD-aura id-only sites out of scope: Wrath-proc/ERA-gated; Titanforge name-shape UNVERIFIED; luac.out debris + desks/journal.md concurrent edit observed, both left alone).
- **Notes:** warrior.lua sits near the 200 chunk-local ceiling (188 after change) — matchers moved above hooks hunter-style + WARRIOR_NAMES_RETRY_S moved up with them. Rogue fixture got a separate UTILITY_AURA_NAMES map (no BY_ID collision). Re-cut 4 stale-contract pins (TBC bare-id / Era name-only / TBC bare lust / Era label precondition) to the new contract.

## 2026-10-22 — [signal:done] sweep complete, all suites green
- 7 fixes + shaman clean proof, 8/8 mutations kill, floor holds. Report filed to orchestrator.

## 2026-10-22 — follow-up: main.lua GCD_OVER unbuilt-hand guard (H3 crash)
- **Worked on:** extended scope by one hunk (no other lane owns main.lua): ST:GCD_OVER (main.lua:1152) indexed get_visuals_frame(hand).gcd_bar with no nil check — under the lazy-bars gate an unbuilt hand has a bare {} table with nil anchor, so get_bar_frame throws "attempt to index a nil value" (H3-isolated in-client). Fix: loop body now skips hands unless bar_is_built (the HU-22 predicate built exactly for this), with a bring_up_hand-style typeof seam guard; comment records that gcd_bar is unconditional with the frame (bars.lua:141, verified — no second guard needed).
- **Current state:** hunk + 1 leg in tests/main_init_state.lua §4b-ii (HUNTER 3-hand boot, offhand anchor torn down to simulate unbuilt, bar_is_built stubbed as the exact bars.lua mirror since the fixture does not load bars.lua): pcall-clean, expiry cleared, mainhand+ranged gcd_bar hidden, offhand untouched. Suites: main_init 984, bars_state 935, bars_lazy 37 — all green. luacheck: main.lua warning is the pre-existing pack-field one (present stashed); full tree 2/0 floor holds.
- **Next step:** orchestrator owns full run.sh; nothing else in main.lua touched.
- **Mutation:** /tmp copy with the guard removed reproduces the exact crash (main.lua:206 attempt to index a nil value) and kills the leg (2 FAILs: the no-throw + the post-throw ranged hide); copy removed.

## 2026-10-22 — [signal:done] GCD_OVER guard landed
- One hunk in main.lua + one leg in main_init_state; suites green, mutation kills, floor holds.

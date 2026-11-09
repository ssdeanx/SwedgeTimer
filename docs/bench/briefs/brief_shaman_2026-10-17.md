# Brief: shaman — build-out round 1
Date: 2026-10-17. Orchestrator-issued, round plan approved in desks/journal.md.

## Read first (all verified on disk)
desks/shaman/journal.md · desks/journal.md · bench/verify_bank.md (S2/S3/S4/S5 rows + §2 17364 row + correction §4.3 — BINDING) · bench/discover_features.md (SuperSwingTimer shaman section) · bench/lessons.md · CAIRN.md

## Scope — writable files (hard boundary)
classes/shaman.lua, weave.lua, tests/weave_state.lua, tests/shaman_state.lua (EXISTS — extend it; run.sh already runs it). NOTHING else — do NOT touch bars.lua or other class files.

## Task
- **S2 Stormstrike nature-vuln bar** (STANDARD): target debuff bar, id 17364 (12s, +20% nature damage), trigger id 32175 noted in verify_bank — guard id reads.
- **S3 WF-fishing HOLD tint** (STANDARD): amber wash / "hold Stormstrike" when WF proc is due (enh-shaman standard delay-SS-for-WF); gate on swing activity (never on st.is_mainline alone — Forever must weave).
- **S4 MW5 spell choice** (correction §4.3 — BINDING): at 5 stacks, LvB ONLY if talent/rune present (SoD rune gate; LvB not baseline in TBC) else LB; keep FS-collision guard (don't overwrite FS <2s remaining).
- **S5 mana tint verify/wire** (STANDARD): verify existing tint paths, wire gaps.
- **Rockbiter Weapon tracking badge** (discover #6): imbue uptime, guarded id read.
- **Lightning/Water Shield CHARGE tracker** (discover #7): we have a shield row — extend with remaining-charge state (3-charge standard); flag as (uncertain) where current coverage is unknown — verify against current code first.
- **S1 totem twist stays BLOCKED** (WF/GoA ids UNCONFIRMED) — do not build.

## Cross-client rules
weave math stays pure (WoW-free) — keep tests/weave_state.lua green (extend only). New toggles nil-safe, defaults documented. Minimal in-place edits, preserve formatting/line endings, no `_` renames, no unused-variable work.

## Validation
bash tests/run.sh — all green. luacheck 0 errors. Mutation proof on /tmp/opencode/mut_shaman/ (break the S4 VoL/talent gate or the FS-collision guard, show the check fails, restore).

## Deliverables
Code · desks/shaman/journal.md entry · signal JSON · bench/buildout_shaman_2026-10-17.md (changes, evidence, charge-tracker pre-check result, option defaults, UNCONFIRMED list). Final reply ≤6 lines. NEVER run git.

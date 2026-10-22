# hunter-followups — Journal

## 2026-10-19 — Desk opened
- **Purpose:** Build the filed hunter follow-ups: trap display, weave/move cues, rank coverage (per bench/hunter_open_2026-10-19.md + bench/hunter_rotation_audit_2026-10-19.md). H2 already cut — verify absence, do NOT re-add. Forever ids stay UNCONFIRMED — do not wire.
- **Scope:** ONLY classes/hunter.lua, hunter_guide.lua, hunter_ui.lua, practice.lua (move-cue checklist ONLY), tests/hunter_state.lua, tests/hunter_guide_state.lua, tests/practice_state.lua (hunter pins ONLY).
- **Out of scope:** lust branch; option tables/config/options_load; guide_contract/smoke/run.sh/TOCs/bars/hud/compat/main/docs/version; bar-frame widgets (file as follow-up); git; invented ids (UNCONFIRMED in caps).
- **Rules:** nil-safe engine-constant defaults, no default-visible change, unknown-hides, st.api.get_time(), swing-activity gating never st.is_mainline-alone. Full harness green + luacheck 2/0 + mutation proofs on /tmp/opencode copies.
- **Next step:** orchestrator validation + in-client checklist (LnL badge on Wrath/SoD; R4/R3 Explosive prompt on 3.80.2; weave checklist in report).

## 2026-10-19 — All three follow-ups built, verified offline [signal:done]
- **Worked on:** (1) Trap display = LnL trap-proc badge (hunter_open §1): `get_lnl_remaining` (throttled 0.5s player-aura scan, 56344/415413 SIM-CONFIRMED + "Lock and Load" UNCONFIRMED fallback) + `get_lnl_prompt` in classes/hunter.lua; `ui.update_lnl_badge` ("HunterLnlBadge", lazy-created, toggle `hunter_lnl_badge_enabled` nil=off, anchor chain after OOM) + hide_all/update wiring in hunter_ui.lua. Badge layer only, engine untouched. (2) Weave/move cues = `HUNTER_WEAVE_STEPS` (trap/melee/move) + missing/hint pure in practice.lua ONLY (prepull comment re-pointed). (3) Rank coverage = Explosive 60052/60053 (sim 434 pair SIM-CONFIRMED/CLIENT-UNCONFIRMED) added to explosive_shot_ids; Steady 34120 already present (verified, pinned). Forever ids untouched (tables still empty); H2 verified absent (no lust code in hunter files, hunter_guide 0 matches).
- **Current state:** hunter_state 597/597, practice_state 1208/1208, hunter_guide_state 1121/1121 (engine untouched, all LnL/Serpent/Sniper pins hold); full harness 37/0; luacheck 0/0 on all 7 touched-or-owned files (tree 3/0: compat + main pre-existing KEEP-ruled, druid_guide concurrent-lane); 7/7 mutations kill with byte-identical restores (/tmp/opencode/mut_hf); endings preserved (hunter.lua/practice.lua CRLF, hunter_ui.lua LF). Mid-session flap (rogue_guide/druid_guide reds) was concurrent-lane crossfire — those suites load only their own guides, final tree 37/0.
- **Next step:** orchestrator validation; owed out-of-scope: options pass (`hunter_lnl_badge_enabled` default off), in-client id/aura confirmation (56344/415413, 60052/60053, LnL aura shape), practice_ui presentation of the weave checklist.

## 2026-10-19 — [signal:done] Hunter follow-ups offline-complete, handed to orchestrator
- Trap display (LnL badge), weave/move-cue checklist, Explosive rank coverage built in scope; 597+1208+1121 pins; 7/7 mutations kill; harness 37/0, luacheck 0/0 on owned files. H2 verified cut; Forever ids untouched.

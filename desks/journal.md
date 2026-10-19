# SwedgeTimer Work Journal

Started: 2026-10-17. Owner directive: new features + fine-tuning (HUD, practice, guides) for all classes/clients. Wire-not-strip: owner ORDERED trace-and-wire of luacheck warnings (replaces the dropped delete-sweep — different job: wire properly to purpose, remove only if purposeless after tracing, never silence with `_`).

Role of this file: the ORCHESTRATOR's central lane ledger (lane table + decisions). Each desk keeps its own journal under `desks/<name>/journal.md`; signals go to `desks/<name>/.signals/`.

## Status
- Harness: **35 steps, 0 failed** (verified in-tree 2026-10-17, four times). luacheck **2 warnings / 0 errors** — the floor (both KEEP-ruled).
- Version **2.1.1** in all 7 tocs + main.lua; zero live 2.1.0 outside history records. CHANGELOG stays [Unreleased] until post-test publish.
- Everything offline-provable is proven. Next: OWNER IN-CLIENT TEST SESSION (TESTING.md checklist). Nothing further can be proven offline.

## Research results (bench/)
- `bench/verify_bank.md` (session ses_eb62a42c0ffe80QtX1qgynSgWO): all 40 banked ideas verified — no dead-ends; 6 corrections (D4 → EMA smoothing; W2 → rage gate; S4 → LvB rune gate; H3 → manual toggle fallback; D1 → talent-name + Wolfshead item 8345; W7 → degrade confirmed). Confirmed ids: BL 2825 / Heroism 32182, JotC debuff 21183 (20s max), SS nature-vuln 17364 (12s), Berserk(cat) 50334 (WotLK), TF rank-dependent → name-based. UNCONFIRMED: Exhaustion 57723/57724, WF/GoA totem ids, Furor talent id, mana-regen probe, target-count sensor.
- `bench/discover_features.md` (session ses_eb62a42bfffeDyiWoX7wtpgSUH): 35 new features (top-15 ranked), 5 differentiators. SuperSwingTimer/TellMeWhen/Quartz/Gnosis/ClassTimer inventoried.

## Decisions
- Wire-not-strip (owner order 2026-10-17, replaces the dropped delete-sweep): every luacheck warning traced to purpose; WIRE if purposeful, REMOVE only if purposeless after tracing (with rationale), never silence with `_`. Whitespace warnings fixed only inside lines already touched.
- Enterprise-grade wave (5 lanes, below): options-grade (warnings + fine-tune), practice-grade, hud-grade, guide-design-grade, core-wiring (rest of tree). Reconcile wave (bars_state/hud_state count pins) runs AFTER all code changes, then oracle audit, then CHANGELOG.
- One-stop-shop north star (operator): swing timer + bars + WeakAuras-style class HUDs + timers in one addon; competitor-scan round 2 feeds the next feature round.

## Lanes
| Lane | Scope | State | Session |
|---|---|---|---|
| bars-design | bars.lua, designmode.lua (C3 service, C6 registration+templates, D3 pips widget, mouse anchoring) | done | ses_eb5df5318ffduR1qQcuMxDmCMj |
| compat-bl | compat.lua (C2 scan_player_aura + confirmed lust ids) | done | ses_eb60843b9ffegBjfNMOWZA7p46 |
| diag | main.lua, diag.lua (C4 tick counters) | done | ses_eb60843aeffefJ11NnGtCKqGGn |
| hunter | H1/H2/H4/H6 + safe-to-move + readiness/feign | done | ses_eb5df5318ffeSg3RjlvLyyneAf |
| warrior | W1/W2(+rage)/W3/W7 + HS tint + ShieldBlock bar + Battle Shout | done | ses_eb5df5333ffeMMDpnuOw46ipLy |
| paladin | P1/P2(21183)/P3/P6/P7 + CD icon group | done | ses_eb5df5332ffeUlDGMx7DiOYEWI |
| shaman-r1 | S2(17364)/S3/S4(+rune)/S5 + Rockbiter + shield charges | done | ses_eb5df5317ffe1jCvgCMU2PaLgK |
| druid | D2(name-based TF)/D3 wiring/D4 EMA TTD/D5/D6 + Omen + tick overlay | done | ses_eb5df5317ffdqmacgPBVt5lnqN |
| practice | C1 harness split + scenarios + design_targets | done | ses_eb5df531effenK1hPJa704dwMw |
| enemy-swing | NEW module + tocs + suite (hostile target swing bar) | done | ses_eb5df531dffe6ULTotxZte2d6o |
| competitor-scan | research round 2 (one-stop-shop gaps) | done | ses_eb5df531dffddYIsM3roxnOIfX |
| shaman-weave | MW 2-3 stacks + spell markers + Flurry ICD | done | ses_eb5df5317ffe1jCvgCMU2PaLgK |
| options | 27 toggles wired | done | ses_eb5b9d746ffedbyOxolplbwnMo |
| options-grade | options-file warnings + fine-tune audit | done | ses_eb5a4cf7bffe5bN5TcUBeQaEOT |
| practice-grade | practice enterprise review | done | ses_eb5a4cf6cffeCedCfhkjNXZ3ro |
| hud-grade | HUD enterprise review | done | ses_eb5a4cf6bffew1tuyUPfMhHCap |
| guide-design-grade | next-action + designer enterprise review | done | ses_eb5a4cf6affeWHF1bvS5OVPhbK |
| core-wiring | rest-of-tree warnings, wire-not-strip | done | ses_eb5a4cf65ffe2SW2m9vHkWyAad |
| reconcile | count pins + Interface pin + whitespace floor | done | ses_eb59d7d61ffe3kR2SfzBxObC5e |
| 120105-matrix | base toc + test pin + AGENTS.md matrix carry 12.1.5 (owner-confirmed) | done (orchestrator direct, verified: toc_check 732/0, CRLF kept) | — |
| options-followup | warrior slot toggles + reset re-anchor + pips probe | done | ses_eb58eab34ffeQDlWT4qsMIZGGh |
| hud-reflow | hidden-slot row reflow (hud-grade §5 #2 closure) | done | ses_eb58eab30ffevKgNhkQrdwtpqz |
| oracle-audit | full-round adversarial audit (Oracle type unavailable → general executed brief) | done | ses_eb57ac25affe6J8S7PripSRFvP |
| oracle-fixes | close R1–R4 + N2/N3 | done | ses_eb5781564ffeRk0sCYQHdPG8co |
| secret-hole-closure | shaman/druid nil-break hardening (R2 remainder) | done | ses_eb5781564ffeRk0sCYQHdPG8co |
| changelog | CHANGELOG + README/TESTING 120105 bump (N1) | done | ses_eb569f45bffeodvV1yyCf62aTq |
| release | version 2.1.0 + pre-publish accuracy pass | done | ses_eb55fa2a7ffeCIopVI4nHLJYP1 |
| version-bump | 2.1.0 → 2.1.1 (8 fields, harness 35/0) | done | ses_eac70cf89ffe5cI49IOIFUTWG3 |
| rogue-research | per-client rogue rotations/hidden-tech/HUD signals (bench/rogue_research_2026-10-19.md) | done | ses_eac70cf7dffeghr8vCgJpHKsz9 |
| feature-hunter | error-path audit H1-H6/M1-M7, verdict NEEDS FIXES (orchestrator-filed) | done | ses_eac70cf7dffdBxC3PCwnSi5SRg |
| feature-proctor | coverage audit G1-G6, verdict ADEQUATE (orchestrator-filed) | done | ses_eac70cf7cffes5O2sznCOWvgui |
| rogue-deep | SS-after-swing CONFIRMED Era / REFUTED TBC + competitor teardown (bench/rogue_deep_2026-10-19.md) | done | ses_eac68336dfferxKDiXZI1dY2bV |
| fix-engine | H1/H2/H3/H5/H6/M1/M2/M7 fixed, harness 35/0 + 8/8 mutations (mid-lane flap from fix-guides half-landed files, self-resolved, no hands-up) | done | ses_eac683369ffeVJ5kLKslA5Fshq |
| fix-guides | H4/M3/M4/M5/M6/R4 + G1-G6, harness 35/0 + 15/15 mutations (bench/fix_guides_weave_2026-10-19.md) | done | ses_eac683364ffeG1pkys0nq5d9lO |

## Rules every lane carries
No git. No lint-config changes. Warning wiring per wire-not-strip (trace → WIRE / REMOVE-with-rationale / KEEP-with-rationale; never `_`). Whitespace fixes only inside touched lines. Endings preserved. Harness + mutation proofs on /tmp/opencode copies. New toggles: nil-safe reads, defaults documented; no default-visible change without an explicit gate.

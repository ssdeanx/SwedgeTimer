# SwedgeTimer Work Journal

Started: 2026-10-17. Owner directive: new features + fine-tuning (HUD, practice, guides) for all classes/clients. Wire-not-strip: owner ORDERED trace-and-wire of luacheck warnings (replaces the dropped delete-sweep — different job: wire properly to purpose, remove only if purposeless after tracing, never silence with `_`).

Role of this file: the ORCHESTRATOR's central lane ledger (lane table + decisions). Each desk keeps its own journal under `desks/<name>/journal.md`; signals go to `desks/<name>/.signals/`.

## Status
- Harness: **37 steps, 0 failed** (verified in-tree 2026-10-19, after rogue skeleton+pure+cues+practice+compat+options). luacheck **2 warnings / 0 errors** — the floor (both KEEP-ruled).
- Version **2.1.1** in all 7 tocs + main.lua; zero live 2.1.0 outside history records. CHANGELOG [2.1.1] covers landings through the SoD-variants wave (bench/release_audit_2026-10-19.md F1 closed). Harness 38 steps, 0 failed (floor).
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
| rogue-skeleton | Slice A skeleton+wiring, 8 TOC appends + run.sh 36th step, 36/0 floor held | done | ses_eac56197ffeA20zNwenWDurOR |
| rogue-pure | rogue_guide.lua pure engine + 194-check suite, standalone green | done | ses_eac56197affepD6mkIquJmA1XR |
| rogue-cues | tick+Era cue+live provider+HUD, 37/0 + 12/12 mutations (rawget probes owed to compat) | done | ses_eac4964f6ffeLo7PGODOzqn740 |
| rogue-practice | 2 drills + options copy, 37/0 + 4/4 mutations (bench/buildout_rogue-practice_2026-10-19.md) | done | ses_eac4964f5ffe32mq77SSoO0wNz |
| rogue-compat | 5 probes→compat + OH-enchant 5th-return latent fix, 37/0 + 13/13 (bench/buildout_rogue-compat_2026-10-19.md) | done | ses_eac171cf2ffezeRyWvVGhR9k0t |
| rogue-options | panel parity + snd-threshold keys, 37/0 + 9/9, 10 cue keys inert (bench/buildout_rogue-options_2026-10-19.md) | done | ses_eac171cf2ffdN6iQq6BUKcyav9 |
| rogue-parity | ST.ROGUE.get_rotation_key (hunter shape) + 10 cue keys REMOVED w/ rationale + loop closure, 37/0 + muts | done | ses_eac017bf8ffejsNVQJFjFCr4kG |
| rogue-diag | ROGUE in diag PROVIDER_CLASSES + pins (186 checks), 37/0 + 8-fail mut | done | ses_eac017becffeMQD6iXkKlNKIUw |
| rogue-docs | README/AGENTS/TESTING rogue entries + [Unreleased] section (TOC 8→7 corrected) | done | ses_eac017bebffe18uv8vgiIuwHx6 |
| rogue-erroraudit | read-only audit, 8 findings (F3 decision + F1/F2/F4/F5 hardenings + F6/F7/F8 notes), ADEQUATE (bench/rogue_erroraudit_2026-10-19.md) | done | ses_eac017bebffdabmaC7z7QA4w52 |

## Reconcile decisions (2026-10-19, rogue wave)
- Cue keys REMOVED (parity lane, wire-not-strip with rationale: HUD slots + guide actions already cover upkeep; duplicate bar presentation adds no signal). CHANGELOG:237-239 now stale (still says "inert, decision owed") → fix dispatched.
- F3 (item-CD unknown→idle): ACCEPT as documented residual (E2-family contract; worst case Tea prompt on real CD → press is no-op; secrecy UNCONFIRMED). No lane.
- F6 (rules 4/5 on unknown family): CONFIRMED intended (all rogue clients have Rupture/Eviscerate; M6 bit suppresses). Pin it, no engine change.
- F7: no action (adequate as-is). F8: moot (pool-band defaults kept, config_presets.lua:580-581).
- Harness re-verified by orchestrator on the final tree: 37/0, luacheck 2/0 (75 files).
| rogue-changelogfix | CHANGELOG cue-key lines rewritten to record parity-lane removal | done | ses_eac017bebffe18uv8vgiIuwHx6 |
| rogue-auditfixes | F1 NaN guards + F2 count check + F4/F5/F6 pins, 8/8 muts, 37/0 | done | ses_eabfd039dffeFpqsx5K1Kwl185 |
| class-matrix | 72 cells: 68 WIRED, 0 MISSING, 4 DEGRADED (D1 hunter order, D2 rogue empty ids by design, D3/D4 rogue bars/design pins), ADEQUATE WITH NOTES (bench/class_matrix_2026-10-19.md) | done | ses_eabf64b7dffeng0Y53Vi6UhzUu |
| rogue-redzone | Era RED SS zone (red default per OWNER ORDER 2026-10-19, gate recorded) + rogue 19/19 wiring, 37/0 + 4/4 muts | done | ses_eabf64b6effe3TnnLGGTPXhptx |
| five-class-gaps | warrior M3-style unmatched counter + pins; rest verified wired; options follow-ups filed | done | ses_eabf64b6effdFRXEiXfiYiAGqH |
| competitor-gaps | ranked implementable gaps X1/W1/D1/R1/P1/H2 (bench/competitor_gaps_2026-10-19.md) | done | ses_eabf64b6dffenJNnyAo72d6euZ |
| release-docs | [Unreleased]→[2.1.1] per operator (NO bump); 8/8 fields verified 2.1.1; stale deferral fixed w/ pointer; late entries appended (rotation/diag/redzone/warrior-counter/audit) | done | ses_eabf64b68ffeozSqUbwb1jJSkU |
| rogue-isolation | read-only: 1 runtime cross-class dep (F1 HIGH rogue→druid_energy) + 0 failing per-client cells + 16 UNCONFIRMED (bench/rogue_client_isolation_2026-10-19.md) | done | ses_eabe2d727ffekpRdJCJvSkE3Ua |
| shaman-icd | lust status + S1 ICD row + weave copy + rogue bars/design pins; own suites green; 33/37 = parallel-lane crossfire (out of scope, morphing) | done | ses_eabe878aeffee84xiiSM3NKfH7 |
| rogue-ema | F1 HIGH closed: EMA vendored into rogue_guide, zero st.druid_energy/ST.DRUID in rogue runtime (comment-only mention :187); 13 equivalence vectors + 26 EMA pins; muts kill | done | ses_eabdecdd2ffeIRT04WYtkWuXo5 |
| druid-ttd-tick-reseal | D1 TTD readout + D2 proc-aware tick + P1 GCD reseal marker; 7 files, 5/5 muts; deviation: no new module (TOC rule), EMA stays in druid_energy (rogue vendored its own copy) | done | ses_eabe878afffelve3QeZHRskxQ6 |
| hunter-tot-analytics | H1 ToT warning + H2 shot analytics + practice report; 8/8 muts; infra fix (sandbox stub leak); owed: options toggles + combat-enter hook | done | ses_eabe878b0ffekx6A25Wd2SPO1M |
| options-hooks | 5 toggles wired (ToT, report, TTD, reseal) + combat-enter reset hook + main_init pins; shaman lust already covered; 6/6 muts; 36/37 (bars pins = reconcile-owned) | done | ses_eabdb2294ffeOUUDMMzVcDibM7 |
| warrior-desync | W1 desync spark (tazUI precedent) + pure sync math + 30+18 pins, 6/6 muts; W2 filed follow-up (not separable); completion notice lost, result pulled via task_result | done | ses_eabe878d0ffe78UzfD09d3ZEnk |
| bars-reconcile | bars_state pins updated (paladin 11→12, warrior 25→26, druid 6→7; rogue/hunter verified) + warrior desync toggle wired; 37/0, 5/5 muts | done | ses_eabafdf76ffeEj4iFbYWMjGSyh |
| icd-tracker | X1: rogue trinket HUD pins (only uncovered class); probes verified present + CLEU pair; X3 registered-on-all-flavors at code level (in-client appearance UNCONFIRMED); 37/0, 6/6 muts | done | ses_eabad4aceffe9Lo92n0mRrKnxG |
| class-isolation | full-tree sweep: 0 runtime cross-class deps; rogue F1 closure holds; shared infra + own-module reads cleared | done | ses_eab9e7994ffeZXgLygrjFrDsmt |
| rogue-rotation | vs wowsims: Era Rupture CONFLICT(H), no-SnD GAP(H), TBC pool 71, EA/Tea/Rupture/Shiv numbers | done | ses_eab9e7983ffeRAuHBSLfqRecFc |
| paladin-rotation | SoD 0.2s window CONFLICT, TBC CS conflict, Forever Echo-aura conflict, TTD/Holy-Strike gaps | done | ses_eab9e7983ffdp732vT0reR0f4C |
| warrior-rotation | 3 HIGH: ww_ids OP contamination, TBC HS ranks missing, SoD Blood Surge dead; HS floor/OP/Execute conflicts | done | ses_eab9e7982ffelfR97ZM23jE2bJ |
| hunter-rotation | Wrath LnL+Serpent missing, TBC Arcane 27019, SoD Serpent/LnL, Forever sim ids (tables stay empty) | done | ses_eab9e797cffekKP15Wrn18VRGi |
| druid-rotation | Era bite-vs-rip CONFLICT, TBC trick-weaves missing, Forever F1 ceiling conflict, SoD clipRoar/trick gaps | done | ses_eab9e797bffeFIhBMwBjaXL0pZ |
| shaman-rotation | rule-7 WAIT contradicts all sims, SoD slots missing, Era FS over-prompt, WF ICD 1.5s vs hardcoded 3s | done | ses_eab9e797bffdhknemuEqmKALDl |
| sim-defaults-options | all shipped numbers cited or kept w/ reason (65/85 = ERA/WRATH MATCH, per-client tables already sim-exact); 6 panels complete + sim synergy block; hunter_multi_target orphan filed; 6/6 muts | done | ses_eab6abc92ffengDPHFGrmlnP7Y |
| practice-parity | registry already covers all 6 classes (8 drills); S/A/B/C/D/F+nil pinned (hunter H5 no-D by design); 2/2 muts | done | ses_eab6abc7dffe5ZoD6O5KXVxjV3 |
| hud-guide-verify | all 6x4 systems WIRED in-tree; D1-D4 hold; remaining gaps need out-of-scope files (filed) | done | ses_eab6abc7cffe2EKaVsjI0IOPCQ |
| warrior-followups | Sunder/Rend upkeep, SoD OP stance-dance, stance handling, Wrath/SoD floors, hamstring engine; 770+1085 pins, 15/15 muts (caught a real gap pre-land); W2 stays unbuilt | done | ses_eab601809ffdizpeMuGOq0STh5 |
| paladin-followups | stopattack discipline, prepull guidance, SoD seal-maintenance, SoD variants scoped, cast-time probe, mana/hard-wait groundwork, rank-1; 84/477/84 pins, 10/10 muts | done | ses_eab601809ffeHqPv69caGnJK2L |
| hunter-followups | SUPERSEDED — re-rowed below after restart (running row kept for history) | — | ses_eab601808ffe8BJ1jYayXwLA3o |
| druid-followups | trick/pooling, FF plumbing, W1 latency, Forever Berserk hold, RipCP override, fight-elapsed gates; 95324+496 pins, 10/10 muts | done | ses_eab601801ffe6HD7U12fB1vxnM |
| rogue-followups | Shiv TBC gates, SoD SnD/Tea lines, Cold Blood slot-less verdict, per-CP rupture rows filed; 622+412 pins, 16/16 muts | done | ses_eab601800ffeMSam2zm3q8cAwn |
| shaman-followups | TBC twist mana-pause + FE lineup pure helpers + 21 pins, 4/4 muts; autocast/GoA/downrank/FE-display/Forever-totem/Searing/hold-SR-ES/CL-sensor/Wrath filed w/ reasons | done | ses_eab601820ffeAVcEA46aLuBHgq |
| templates-build | per-class HUD template select + Custom fallback + persistence; 18 templates, 813-check suite, 7/7 muts, 38/0 | done | ses_eab58a608ffeUPXpQSLmCGdaNm |
| rogue-rotfix | SnD upkeep + Era Evisc-first + per-client EA/Tea/Shiv/builder rules; 433+385 pins, 13/13 muts; no new slots/keys (filed) | done | ses_eab9881bfffezecOw7LsFXxap4 |
| paladin-rotfix | ICD discipline + SoD 200ms window + TBC pull-hold/reseal-guard + Forever echo folding; 84/477/295 pins, 15/15 muts | done | ses_eab9881beffeMdZvDpNRQEMnny |
| warrior-rotfix | ww_ids→1680, TBC HS ranks, SoD Blood Surge aura, HS floors, WW-delay, OP fast path, hamstring engine; 697+1007 pins, 11/11 muts | done | ses_eab9881beffddbKeaNg95wV9qz |
| hunter-rotfix | LnL arms + Serpent guard + TBC Arcane arm + Sniper bypass; +67 pins; bridge-crossing filed as follow-ups | done | ses_eab9881b0ffeahmUBpTLt8Z5aD |
| druid-rotfix | 14 gaps (Era E1, SoD Roar-clip, TBC 10s, Wrath dynamic TF, Forever 50-ceiling chain); 95214+473 pins, 10/10 muts | done | ses_eab9881afffe5McZ0O78AIrbhP |
| shaman-rotfix | rule-7→opt-in, Era FS veto, SoD slots+SR, TBC Magma/FN, WF family ICD, shock-capped ES; 465+765+420 pins, 6/6 muts | done | ses_eab9881aeffe374Q5HcXC5LREP |
| sod-detect | no offline SoD-vs-Era discriminator; per-class ERA+known-spell mechanism; rogue SOD rule to wire | done | ses_eab7deab0ffe5AtuCUNAkSKFZC |
| open-rules | H6 BUILD; fight-remaining CUT; Victory Rush HOLD DORMANT (operator: SKIP) | done | ses_eab7dea9dffe44GE4V3GLZ1EaD |
| hunter-open | trap/ISS→badges; mana/Viper→OOM+checklist; hawk-count CUT (probe gated); Forever ids CLIENT-UNCONFIRMED; H2 CUT decided (alt-later noted) | done | ses_eab7dea9cffe6Yk29AWd5j4TUQ |
| wrath-sod | druid/shaman Wrath MATCH w/ cuts; SS swipe no-branch; paladin SoD variants = separate rotations (backlog) | done | ses_eab7dea9cffdX5I8mqYJusRgci |
| w2-hunter-badges | W2 full build + RF 2x/ISS tint/OOM badge + checklist + toggles; H2 lust branch EXCLUDED (pending this decision) | done | ses_eab7b8027ffeqokES5QPLmokDg |
| rogue-h6-sod | H6 wait-HOLD + Forever suppression behind ea_duty + ENVENOM SOD-rule wiring; no new toggles | done | ses_eab7b801affeKAw4LthYWVHxeE |
| h2-cut | lust-gated Steady cue cut per operator (sim-faithful); re-enable path documented for alt-later opt-in; 569/1121 pins, 4/4 muts | done | ses_eab7209ccffemO51fFT6TnPdpB |
| hud-templates-design | 2-3 named templates per class + preview/selection story + itemized build scope (bench/hud_templates_2026-10-19.md); design-only, no code | done | ses_eab5ac620ffegIWiejc3Ma0c3J |
| rogue-icons | guide + HUD slots for snd/ar/bf/cb; no options changes (filed follow-up) | done | ses_eab46637fffeLKgCIkWc2fEE |
| warrior-bloodfrenzy | SoD Rend-rune probe un-frozen to operator-confirmed 412507; 773 checks, 4/4 muts | done | ses_eab466378ffeRumtmDqRW5CzBr |
| hud-reconcile | rogue 12→13 slot pin + order/trinket pins in hud_state §19; 462 checks, mutation-verified; 38/0 | done | ses_eab3f8ef3ffeMW73QRioXy1B3d |
| hunter-followups | LnL badge + HUNTER_WEAVE_STEPS + Explosive ranks; signal lost on restart, orchestrator verified in-tree 38/0 | done | ses_eab601808ffe8BJ1jYayXwLA3o |
| options-megapass | LnL + coldblood + mana-threshold wired w/ pins; hard-wait/shaman-hold/RipCP correctly unwired; 1381 checks, 4/4 muts | done | ses_eab3c5998ffepGMUx9xxPYwVY9 |
| warrior-hamstring-slot | hamstring-weave filler into guide + HUD slots on existing engine | done | ses_eab3af12dffeI5kHWJz0hiWYOB |
| rogue-rupture-rows | 1CP/5CP Rupture DATA + accessor, no behavior change; 2/3/4CP + glyph + CttC filed | done | ses_eab3a97fdffelPaw4mRHYJxIiz |
| shaman-searing-clock | fight-clock stamp + Searing reader; FE display stays filed | done | ses_eab3a73a1ffe27tk5V6IK3Ca5H |
| paladin-hardwait | WAIT render on hard_wait, rank-1 filed (icon dup); 5/5 muts, 38/0 | done | ses_eab315f2effeBSuuUwgblIjyB7 |
| shaman-mana-sres | twist mana gate + family thresholds + ES floor consume; gather/options filed; 5/5 muts | done | ses_eab315f24ffey4MQz7saU5LYBY |
| druid-ripcp-gather | rip_min_cp passthrough (nil→default 4); widget shape filed; 6/6 muts, 38/0 | done | ses_eab315f23ffe4QFD2H46nIlK8q |
| options-ripcp | guide_rip_min_cp widget + default 4; hold/SR/ES/rank-1 correctly unwired; 7/7 muts | done | ses_eab2b7b9affe1n0rc5U1ESwL2H |
| shaman-twistfeed | TBC 0.10 feed live, nil elsewhere; SR already traveling; 5/5 muts, 38/0 | done | ses_eab2b7b95ffe4S97PpiCpojvCd |
| diag-ids-errors | WANTED_IDS (67) + error ring via seterrorhandler chain, print-only, capped; 236 checks, 8/8 muts | done | ses_eab16ec93ffeql1awEXYgzQHRF |
| hunter-multitarget | FILED BACK — zero edits; audit specifies no multi-target rule (orphan stays); 38/0 | done | ses_eab162c5affe0s1Ld0db7zc0Qw |
| wrath-leftovers | CONFIRMED table + 12-item missing list (incl. CoE M3 for triage); research-only | done | ses_eab162c4fffeMSKyj3bCB6ovpn |
| sod-paladin-variants | Twist/Exodin MATCH; Seal-stacking/Shockadin/Wrath-like BUILD w/ APLs; research-only | done | ses_eab162c4effekVOwTciKOw2ae7 |
| druid-ffclaw | W1b fish + waitForFf + F6c omen-fish; Claw slot 6→7; 10/10 muts | done | ses_eab162c4effd654EcgJc6smWQX |
| sod-variants-build | seal-stacking + shockadin + SoD-wrath wired per APL; HS/AM slots + infusion filed | done | ses_eab0b4458ffeBybLoGFU9cVuBM |
| coe-m3-triage | FILED cut-with-reason (14th slot + water clock + 66842 unconfirmed); zero edits | done | ses_eab0b4418ffeNlO0dAPY1UuH7T |
| release-audit | NOT READY verdict: CHANGELOG/TESTING/ledger stale (F1-F3); report-only, zero edits | done | ses_eab00d1e6ffeY55M7qxK63WSGv |
| live-test-script | per-class Era/SoD+TBC checklists + diag-paste + U1-U17 table; NEW bench file | done | ses_eab00d1e2ffestXrcKuMUiLkEt |
| release-docs-fix | F1-F3 closed by orchestrator: CHANGELOG wave entries, TESTING 2.1.1, ledger line 9 + dup row | done | — |
| rogue-hunter-sweep | Era/SoD/TBC green all 4 systems, zero edits; H-HUD-1/2 filed | done | ses_eab016451ffexIijEdf9NZHMAP |
| paladin-warrior-sweep | Era/SoD/TBC green all 4 systems, zero edits; HS/AM + warrior rules filed | done | ses_eab016448ffekBwJKZf15mwLrQ |
| shaman-druid-sweep | Era/SoD/TBC green; FS 12s fight gate built (SoD/TBC) + 13 pins, 4/4 muts; G1/G2 filed | done | ses_eab016448ffdoU2cfTOR1Wwyet |
| curseforge-readme | README rewritten (pitch/clients/classes/install/commands, no bloat, GPL-3.0 fix); icon in 7/7 TOCs | done | ses_eaaf56d46ffeipVwR04OUB1yI0 |
| hunter-resweep | 5/5 fixes hold; 1 new HIGH (missing MONK/DH/EVOKER stubs); filed by orchestrator | done | ses_eaaf2f3b7ffeuygfA6RMet8AyF |
| class-stubs-fix | MONK/DH/EVOKER stubs (Retail nil-index); no site changes | done | ses_eaaeefa34ffeFoNgDOYeDyUtVg |
| display-render-wave | HS/AM slots 8→10 + UI mapping; hunter Era 6-slot pick; 6/6 muts, 38/0 | done | ses_eaaecfaebffe4gWazTT9zKbt2d |
| settings-audit | per-class missing/copy/order spec (2 real bugs: maul desc, order collisions); build queued on designer lane | done | ses_eaadca3f9ffeoGF8loeck9iAWB |
| designer-templates | coldblood + hamstring in templates; per-class designer functional; G1-G4 filed | done | ses_eaade073affefsrWDkqaW55thv |
| settings-build | audit spec built: maul desc, order collisions, copy, alignment; 3/3 muts, 38/0 | done | ses_eaad7d439ffeKo18H0Frxf2yAl |
| weakaura-templates | Dora swing timer + enhance + weaving indicator mapped; scrape recipe found | done | ses_eaad91f62ffeiibADSSiDjnxey |
| perclient-audit | harness RED (crossfire); name-vs-id rule PARTIALLY overstated; compat bugs filed; G1-G8 | done | ses_eaabf8ba6ffe5OcD3QHmpLXS9S |
| wa-gallery | shortlist mapped to template labels, pinned; 4/4 muts | done | ses_eaac227d5fferMPCdo7VQd093B |
| hunter-wa-consume | TBC-name/Era-id wiring + pins; WA-only extras filed in hunter_wa_map | done | ses_eaac69921ffexuGzejFMWo37sH |
| rogue-nameid | get_spell_query helper + 12 id-use classes converted; 8/8 muts; parity-cb stub filed | done | ses_eaac227d6ffdigD6h048a6rDsK |
| parity-cb-stub | stub answers "Blade Flurry" name; parity green; 4 paladin pins left to running lane | done | ses_eaab9bb88ffedx3aXRcu6LxBcB |
| shaman-druid-nameid | spell_query funnels both classes, both resolutions pinned; 6/6 muts; 2 paladin reds left out | done | ses_eaac227d6ffeKthM1EH4GWJusC |
| paladin-warrior-nameid | TBC-name/Era-id conversions + contrast pins; 6/6 muts; HU-5 raised (fixtures) | done | ses_eaac227e4ffe7aJARUMiVG3Aly |
| compat-fixes | C_SpellBook probes, CLEU mainline gate, ShapeshiftForm fallback; 5/5 muts | done | ses_eaab3285fffenexJ4ocjKEqjKE |
| hu5-rekeys | fixture name-keys applied, hud/guide_contract green; 1 hunter red left out | done | ses_eaab12e8affeqqmf2QpvpZjIRw |
| shaman-g1 | SoD sub-5 weave fit (5b/12b) + gather; 6/6 muts; G2 stays filed | done | ses_eaab3285effewjxM7Y60U99ZZW |
| hunter-distance | weave_band over LRC fields + verdict mapping; prog spec filed for widget lane | done | ses_eaab32858ffecuxrTDWxFeVPbT |
| cleave-tint | default kept (icon-hue match), off-toggle pins added, no prod change | done | ses_eaa7fff9fffey1eQAQkiJLc12v |
| hud-parity | rogue GCD swipe + paladin 10v7 + druid Claw HUD gaps specced; warrior at bar | done | ses_eaa7fff9fffdsKtJ8xO0W0Bn9M |
| wa-rescrape | all 5 URLs CONFIRMED live; slug verdict; bench evidence logs | done | ses_eaa82958effeosC2Y2J54EMVq7 |
| gap-closure | 3 compat gaps CONFIRMED-fixed; 5 gap defs lost to truncation — needs re-dispatch | done | ses_eaa825f41ffeOmZhhudKIv5NnO |
| hunter-weave-prog | step/update prog + toggle; 8/8 muts; display lane unbuilt | done | ses_eaa82958fffe1dWY1hUBRMjVHI |
| rogue-gcd | running-GCD swipe on all 9 slots; 4/4 muts; 1 paladin crossfire left out | done | ses_eaa7c7273ffeDzxDs6uYIk2yKJ |
| druid-claw-hud | Claw HUD slot display-only (nil=off); widget filed; 5/5 muts | done | ses_eaa7c7269ffddpm8Xqsi7b5sXI |
| paladin-hud-mirror | 5/6 slots mirrored (twist deferred), HS/AM lit/withheld pins; 3/3 muts | done | ses_eaa7c7269ffeglXJpxrJexfuoN |
| options-widgets | kidney/restealth/bandage + claw widgets + defaults; 7/7 muts | done | ses_eaa748207ffegIFy2Z8OX8Uy1n |
| paladin-ui | STOP/PULL/OOM/WAIT chain + mana mapping; rank-1 stays filed | done | ses_eaa748206ffe4VLrNHctHBJ03p |
| hunter-traps | trap placed machine + Clever mult + rotation tiers; active phase filed | done | ses_eaa74820cffe1M0RCNk9QnwLdW |
| trinkets-usable | usable-only gate; passive/unknown hidden; 3/3 muts | done | ses_eaa748205ffexQWCTL5a9oDgGY |
| warrior-styles | 7 ranked cards, TBC/Era/SoD only | done | ses_eaa79753affeFGsSoDS0zyKuKW |
| rogue-styles | 14 ranked cards, Redtuzk top TBC | done | ses_eaa79752dffeXKif9x7DeTbb92 |
| druid-styles | 7 ranked cards, Sabimaru top | done | ses_eaa79752dffd2Z0h7s9U0yeyOg |
| paladin-styles | 10 ranked cards, Surveillant twist timer top | done | ses_eaa797529ffe6eiib6Q5lvdn0F |
| shaman-leftovers | 0-1 hardcast + Wrath M1 sub-5; 6/6 muts; weave-lane alignment filed | done | ses_eaa74820bffe1VpYOBQlsPEmQn |
| firecrawl-tooltest | no standalone extract; scrape-only; search/agent broken server-side | done | ses_eaa6c35d5ffeSUphENINo5t2ll |
| warrior-rules | Sunder/Rend/stance-dance/hamstring rules live; floors HELD; VR SKIP; 8/8 muts | done | ses_eaa74820affezqXq7sJRiCUI21 |
| hud-finishing | gallery shortlists applied per class; rogue reconciled; 7/7 muts, 38/0 | done | ses_eaa652a58ffe1Wuqz24GoxmEZy |
| final-hunter | N1-N4 unguarded drivers (guide/HUD/label/practice); fix lane dispatched | done | ses_eaa5e01b4ffeZT9pz5zwdem9jU |
| final-proctor | READY, ~97% offline, no blockers; M1/M2/M3 moderate filed | done | ses_eaa5e01b3ffebqVyA27e7MUCcQ |
| driver-containment | N1-N4 run_guarded extension + M1 prog filed-row pin; 38/0 | done | ses_eaa5a90b4ffeftwFG57MU2guTt |
| release-docs-final | README class lines + templates; CHANGELOG final-hardening section | done | — |
| readme-production | class table + colors, practice/HUD/designer sections; no invented integrations | done | — |
| hunter-weave-prog | step/update prog + toggle; 8/8 muts; display lane unbuilt | done | ses_eaa82958fffe1dWY1hUBRMjVHI |
| rogue-gcd | running-GCD swipe on all 9 slots; 4/4 muts; 1 paladin crossfire left out | done | ses_eaa7c7273ffeDzxDs6uYIk2yKJ |
| druid-claw-hud | Claw HUD slot display-only (nil=off); widget filed; 5/5 muts | done | ses_eaa7c7269ffddpm8Xqsi7b5sXI |
| paladin-hud-mirror | 5/6 slots mirrored (twist deferred), HS/AM lit/withheld pins; 3/3 muts | done | ses_eaa7c7269ffeglXJpxrJexfuoN |
| full-feature-wave | rogue/druid widgets (O), paladin UI (P), hunter traps (H), shaman 0-1/Wrath-M1 (S), warrior rules+contract (W), usable-only trinkets (T) | running | — |
| sod-hud-font | SoD Font-not-set crash: font-before-SetText + FRIZQT fallback; 3/3 muts, 38/0 | done | ses_eaa0e9badffe306L0fEY3w17r2 |
| sod-options | practice absence correct+filed (S1); design_toggle hollow-guard, residual filed (S2); 38/0 | done | ses_eaa0e9ba7ffeQ7Vz7gJcTmR9jH |
| practice-every-class | top-level Practice tab + all-6-class routing | halted-superseded | ses_eaa060df6ffexsra4W8hpX7E1H |
| designer-every-class | per-class descriptor audit + gap closure (no option_tables) | halted-superseded | ses_eaa060df0ffeM1IW0rs47rM3zw |
| paladin-pd | paladin practice + designer, full class scope | done | ses_eaa01e214ffeZUY2KmNtjrkmar |
| warrior-pd | warrior practice + designer, full class scope | done | ses_eaa01e202ffeldZqKcJk684KzR |
| hunter-pd | hunter practice + designer, full class scope | done | ses_eaa01e201ffejGoMJfPHCSFO7O |
| rogue-pd | rogue practice + designer, full class scope | done | ses_eaa01e200ffePpgnl1ZZIRsX9u |
| reconcile-pd | SODOPT flips + design count pin + 4 dead-hook callers; 38/0 | done | ses_ea9e5ea91ffeHuy2WD2Kku1Uk3 |
| audit-wave | hunter missing-sweep + proctor sufficiency (read-only) | done | ses_ea9dc4965ffevK3wn2AJ7goc1a / ses_ea9dc4964ffe3cfbqmpliAxfuV |
| hardening-pd | H1-H8 + M1-M6 + G1-G3 + G6 (rulings: H6 report-stands, M4 rewrite) | done | ses_ea9d83e66ffeYVa3r8rYUG2bdh |
| changelog-pd | CHANGELOG [2.1.1] + TESTING wave entries | done | ses_ea9caf619ffet0vmpYsC5rI786 |
| sod-practice-font | result-frame font-before-SetText; all 30 sites verified; 38/0 | done | ses_ea9c27bedffeXAKMaindElENB6 |
| swing-guard | nil-bar guards in SWING_TIMER_* + first-notice; 10/10 muts, 38/0 | done | ses_ea9ba3a0affeSJ17wkf9SWTRgK |
| defaults-behavior | guide+HUD on by default, Behaviour populated, paladin-parity gaps closed | done | ses_ea9b4982fffe1wi3ae3ZDdduWD |
| practice-debug | silent no-start gates → speak + cross-class audit | done | ses_ea9b4982affe3MwZZQ8Bt3y3WS |
| sim-resources | rage/mana/focus/energy in sim (warrior rage first) | done | ses_ea99f0d75ffeVuEKrJvG0N7vNo |
| hunter-seam | per-client cast-time fallbacks + calibrated latency; 6/6 muts, 38/0 | done | ses_ea99bb585ffemRICjNS2D40ycC |
| shaman-g2 | WF/GoA guide slots (15) + rules 8b/8c; HUD deferred+pin; 38/0 | done | ses_ea99bb58affejsUlGnGRnH2hB9 |
| deep-audit | hunter deep sweep: F1-F14 (2 material), call-path + API truth tables | done | ses_ea98586ecffepElQEB3S89Vj3M |
| class-order-parity | F8/F9 order unified (guide->HUD->practice) across 6 classes; 8/8 muts | done | ses_ea97ceaa6ffdiuwwLqfjrXNcCE |
| gamification-foundation | pure practice_progress + practice_stats + unlock registry; 51/51 muts, 40/0 | done | ses_ea98ffadeffeEikw0SGJJ47vF3 |
| audit-f6-toc | base TOC narrowed to classic-line (CLEU lib throws on mainline); toc_check 816/0 | done | — (orchestrator) |
| diag-truth-fix | F1 ring install + F2 has_oh + F3/F5/F7/F11 | done | ses_ea97ceaa7ffe5R7Z3QnO2zDAiK |
| tbc-resolution | F4 name-vs-id family resolution + branch cites (HU-6 filed) | done | ses_ea97ceaa6ffeWHYdLP9XZzl0s9 |
| bars-print | F12 bars.lua print path | done | ses_ea97ceaa1ffeyj7uMC1tghqSa1 |
| resolver-callers | hunter 10 sites + warrior slam fallback → state API; 13/13 muts | done | ses_ea953261effeY1ugmX9lsXw0dd |
| progress-page | Progress page + stats frame + sparkline; 33/33 muts | done | ses_ea96cd0f3ffeADECxi2iPKUd1J |
| practice-hook | XP/level/mastery live + badge (off by default); 26/26 muts | done | ses_ea96f32b8ffe7aRiRghf7X1M7t |
| class-features-audit | per-class checklist + 18 drills + 6 scenarios spec | done | ses_ea963d881ffeppbhb7HV76mLqI |
| paladin-scenario | paladin rotation + 3 drills + engine-order reuse; 12/12 muts | done | ses_ea943a67bffdoE6ag691r6aFqh |
| scenario-engine | rotation-run engine + drill routing + SUPERSEDED map + HU-7 fix; 41/0 | done | ses_ea943a67bffeLKeq2wtqsQ4U8Q |
| shaman-slots | LS/CoE/Searing guide slots + contract + HUD mirror | running | ses_ea91c698cffer92sZdY4lQ8wOg |
| superseded-wrappers | class wrappers start own drill; shaman alias dropped | running | — |
| warrior-scenario | warrior rotation + drills + twist-session fix; 27/27 muts | done | ses_ea943a665ffeYWbk02dPKXUtrK |
| shaman-scenario | shaman rotation + 4 drills; found namespace break (HU-7); 18/18 muts | done | ses_ea943a65bffeqb8p8l12Y6OWFg |
| druid-scenario | druid rotation + drills + sim-aligned powershift; 13/13 muts | done | ses_ea943a663ffe8nSJ4bkex7ZtSz |
| print-policy-2 | main.lua alias + config_presets print; config.lua fixed by orchestrator | done | ses_ea96cd0f4ffeiifFrUKN6lXhlD |
| progress-page | Progress options page + stats frame + sparkline | running | ses_ea96cd0f3ffeADECxi2iPKUd1J |
| class-latch | druid/warrior absent-vs-unresolved latch; 10/10 muts | done | ses_ea966718dffe5F1Sv553lxUw3K |
| resolver-callers | hunter 12 sites + warrior slam fallback → state API | running | — |
| practice-hook | progress wired into live sessions + badge | running | ses_ea96f32b8ffe7aRiRghf7X1M7t |
| f10-shared-guard | 6 run_guarded copies → 1 shared helper (needs practice_ui + TOCs free) | queued | — |
| class-features-audit | per-class feature checklist + target drill set (≥3 drills/class) | running | — |
| drill-build-queue | implement the audited per-class drills + features (needs practice.lua/practice_ui.lua free) | queued | — |
| practice-hook | progress wired into live sessions + badge | running | — |
| stale-pins-flip | 6 suites' false-default pins → new true defaults (wiring excluded) | done | ses_ea9a9aa33ffeiHsSjOq5R85gFI |
| hud-key-g1 | 5-class HUD key parity pins; hud 599→660 | done | ses_ea9a550e7ffeOmrN2v3ZdjKdUU |
| f10-shared-guard | one shared isolation helper (6 copies→1) + SCENARIO_RESOURCE_KEYS crash; 9/9 muts | done | ses_ea8fa3880ffefEv2EXQPQ7t2RC |
| wrappers-repoint | class wrappers run own drill; shaman alias removed; 7/7 muts | done | ses_ea90e0578ffeNFO4I4Q75Kybc6 |
| badge-default | badge+notices default ON (operator gate); 5/5 muts | done | ses_ea8da10f3ffe6LLl1ZF9360Dhx |
| bs1-compat-probes | scan_unit_aura + is_item_equipped; 10/10 muts | done | ses_ea8d5624bffeO11pPsUx4btnj9 |
| bs5-paladin-ids | Forever Echo + Holy Strike ids (name-primary), LCD counter, hard-wait pin; 7/7 muts | done | ses_ea8d56246ffew4C8JXWCpEbmPT |
| bs6-rogue-hemo | Hemorrhage builder + family gate (corpus ids were swapped); 7/7 muts | done | ses_ea8d56241ffez53eO0WVRuJaGh |
| bs2-druid-wolfshead | tri-state probe (reserved, no rule consumes); 3 muts | done | ses_ea8bb6d82ffexqEtJTszbiW6Fe |
| bs3-hunter-serpent | target scan, unknown≠down; 2 muts | done | ses_ea8bb6d81ffeJA7moAqWTHzh77 |
| bs4-shaman-coe | CoE live slot (66842 + water slot 3, client-sourced) + per-family Stormstrike; 23 muts | done | ses_ea8bb6d7dffe4OJ9FFSIsjCtck |
| bs7-options | Forever Rend toggle, mana threshold, FS default→0, badge widget (HU-9); 11/11 muts | done | ses_ea8bb6d83ffe38Qkhj2QQSWu1f |
| closure-triad | CoE widget, FS gather fallback→0, druid hot-read throttle; 5/5 muts | done | ses_ea8f1f4ffeOg9FW3Q5fb8hQY |
| docs-truth | CHANGELOG wave + TESTING + README + spec export correction + live script §7 | done | ses_ea889398affeEVWS0hSgcFnhyh |
| engine-hold | HU-8 hold verdict + diag counter + pull clock + drill routing | running | ses_ea892f1f5ffeTVfGT5JLxsjbxt |
| warrior-hs-queue | HS/Cleave queue drill + Forever Rend read + warrior HUD mirror | running | ses_ea892f1f5ffdeLojhz1M77J4Tn |
| class-hold-statements | 5 class files state their hold (+warrior later) | done | ses_ea8764925ffeCJIQhy1z0MNiEo |
| scenario-100-audit | per-class 8-criteria audit (2 CRITICAL found) | done | ses_ea8689119ffeQo3bvha8Xf8iod |
| final-audit | post-everything deep audit: 2 HIGH + 4 MEDIUM | done | ses_ea695d965ffdvft69relFIsJw7 |
| druid-hold-fix | H1: druid hold→action (points for idling / false F); 5/5 muts | done | ses_ea676b795ffeLoL9bNJYRQZofw |
| session-flush | H2 logout flush + M1 reset mid-session + M4 daily-cap freeze; 9/9 muts | done | ses_ea676b794ffeblyg4LnHWM9YuK |
| paladin-gate-widgets | M2 families gate + hor/how_wrath widgets + templates + citation | running | ses_ea676b78cffe1uR4MZI5GkFAXc |
| compat-known-contract | M3 is_spell_known doc/code contract | running | ses_ea676b78cffeEu9rnXp5S6QDoh |
| paladin-hud-band | HoR + HoW (Wrath) HUD mirrors; 9/9 muts | done | ses_ea695d965ffeLhx6utQCDFA64D |
| paladin-apl | paladin utility layer (5 rows, 2 armed) + 11-row prepull; 14/14 muts | done | ses_ea7a0ca72ffeYrWYJcUgPaHMhV |
| docs-wave2 | CHANGELOG/README/TESTING + live script for the wave | done | ses_ea7a0ca72ffdB4oIIpsUSE16MA |
| warrior-utility-live | 13 utility lines live + prepull table; 13/13 muts | done | ses_ea82ed396ffejMFxJ2IjAzVeTU |
| hunter-utility-live | 18 utility lines live + strip growth; 11/11 muts | done | ses_ea82ed395ffen0zYSBdif6pr3p |
| rogue-utility | 24 utility rows + arms; 24/24 muts | done | ses_ea82ed390ffeaA5F35hzGUwDMj |
| druid-utility | 7 spine rows + 4 arms; 21/21 muts | done | ses_ea82ed38fffeqQxRC6P3ECC6vu |
| shaman-utility | 4 rows + arms + prepull; 14/14 muts | done | ses_ea82ed38fffd7xaTTpl6oxERsO |
| residuals-4cls | warrior/rogue/druid/shaman residual reads + honest flags | done | ses_ea7cf5d56ffeQSQYO3v5FQyT8W / ses_ea7cf5d55ffeg2T01CK1nVADSV / ses_ea7cf5d55ffd274gR7KpbDxiMm / ses_ea7cf5d50ffe7pEOc1Ztj0XxT0 |
| bench-corpus | 31 id corrections + 17 bench files (dated notes) | done | ses_ea7cf5d50ffdwpaZ0PWTo7zHMj |
| progression-audit | gamification surface: 2 HIGH (cap wall, unreported swallow) + 5 MED | done | ses_ea616dd2cffeWFceVBxbz3Z2Ok |
| docstruth-audit | docs+script: 18 findings (5 HIGH phantom-defect steps) | done | ses_ea616dd2bffemQkB0t3MTrAaWb |
| progression-pure | H-1 cap floor + M-2 account scope + M-3 sentinel + L-1/L-4/L-6; 11 muts | done | ses_ea60a9759ffeuIWdcJKtCZk6Kp |
| progression-ui | H-2 cap notice + M-1 loud refusal + M-4 streak + M-5 arm expiry; 8 muts | done | ses_ea60a9759ffdurPBiEQ4wyu5jn |
| script-docs-fix | F-1..F-5 HIGH (diag verb, SnD, Era pre-pull, names) + F-8..F-13 | done | ses_ea60a9758ffeyB523TZC5tquw7 |
| pick-channel-gap5 | 6 real grader shapes driven end-to-end; 12/12 muts | done | ses_ea618ddf0ffeAJDfeqnD240E0U |
| shaman-family | B1: family-scoped rotation+slots; 9/9 muts | done | ses_ea618ddf8ffeDraOpgh2rMffpG |
| hunter-hud-id | B2: HUD steady id per family + Forever slot drop + strict flags; 8/8 muts | done | ses_ea618ddf7ffeARTd6Md7FbTzb6 |
| progression-callsites | §7.1-§7.5 call sites + pick-contract F-1; 7/7 muts | done | ses_ea5e105c0ffe12M1QUc0LU2Wg8 |
| prepull-contract | strict flags + contract suite + citation-only marking | running | ses_ea618ddf1ffeN3J4FMObHrrDaP |
| hunter-hud-slots | remaining HUD slots family-corrected | running | ses_ea5e105bfffeJke13oW4IBEcKj |
| changelog-truth | CHANGELOG F6/F7/F8/F14-F17 + new wave entries; 43/0 | done | ses_ea55c2b98ffeRfN4XhBSB652f9 |
| panel-common-actions | paladin/warrior/rogue/shaman common abilities + neutral sets; 9/9 muts | done | ses_ea577e007ffexvKHi3T16jGWOg |
| hunter-sod-build | SoD-aware HUD slots (Chimera probe, no new read); 10/10 muts | done | ses_ea5829c9cffe8vzix7udZuumgT |
| neutral-hunter-druid | hunter+druid common abilities + neutral sets; 14/14 muts | done | ses_ea54cf5beffebjimUyX1VzBvL5 |
| neutral-buckets | Cata/Mists coverage: offer only what is neutral or ranked; 10/10 muts | done | ses_ea5339a7effehmWoGxZGtHZltV |
| final-gate-audit | FINAL deep audit (0 HIGH gate) | done | ses_ea50b69a7ffeT9t274D7oLIr6m |
| final-gate-tests | FINAL test sufficiency + harness registry | done | ses_ea50b69a7ffd9pqufXAZJ1ejAS |
| grader-seam | HIGH-1: one button per spell + grader normalisation (M1/M2/M3 each the only guard) | done | ses_ea4e17c5affeWTYMj1IVfraBVC |
| local-headroom | HIGH-3: headroom 200→185/181/179 + compiler-count guard; MED-1/2/3 | done | ses_ea4e17c59ffe4S24Omf12wkP3V |
| stale-claims | false "rank art" claim cleared at 11 sites; guard extended to 6 classes | done | ses_ea4863436ffe4mmJg51o8M3Hls |
| final-reaudit | publish-gate re-audit: 0 HIGH, 1 MED, 2 LOW (all pins) | done | ses_ea4771967ffeXEd8IABafiTlpy |
| publish-gate-pins | F-1 collision pin + F-2 CHANGELOG pin + F-3 de-self-reference; 12/12 muts | done | ses_ea464caeeffei7CPS2x2S95wat |
| font-sweep | hunter_ui 4 sites + bars nil-path + shared utils.apply_font; 6/6 muts | done | ses_ea454cc0cffejGaSQcjBQ8p1Tv |
| font-remainder | practice_ui/designmode/nextaction_ui/rogue chain-routed; 82/82 sites safe; 14/14 muts | done | ses_ea42cf400ffeQMz5fCH37svMy4 |
| class-mirror | rogue+hunter namespace mirrors removed; wiring_check 7a/7b/8 guards | done | ses_ea451e680ffex0RhlcPMDcdTyd |
| perclient-truth | P1-P8 answered offline; P9-P12 handed to the operator | done | ses_ea464caedffekhlZkgNDUBDnCz |
| live-script-probes | P9-P12 merged into the operator's script | done | ses_ea44d074affeG8Gh2zSiJmac5l |
| release-readiness | version truth, TOC coverage, media, publish checklist | running | ses_ea50b69a3ffeho4fG41TPP7VZ1 |
| prepull-contract | strict flags + contract suite (124) + citation-only markers; 9/9 muts | done | ses_ea618ddf1ffeN3J4FMObHrrDaP |
| neutral-engine | neutral outcome (no attempt/points/streak) + NEUTRAL popup; 3/3 muts | done | ses_ea59c262effeJuNBvHQCYkQ26J |
| class-neutral-4 | paladin/warrior/rogue/shaman neutral sets + closed-list suite | done | ses_ea59c262dffeTF3ASW8Cpu8poK |
| final-gate-audit | post-everything re-audit (0 HIGH) | queued | — |
| druid-pd | druid practice + designer, full class scope | done | ses_eaa01e1faffe9tfZecasTrp2je |
| shaman-pd | shaman practice + designer, full class scope | done | ses_eaa01e1faffda7y1lTku652B3D |
| reconcile-note | 3 harness reds are running-lane crossfire (design registry growth, shaman-practice pins, wiring dead-hooks) — reconcile when all six land; druid own suites 602/602 | open | — |
| compat-f4 | audit F4: compat.get_family_spell_id walks the rank table through api.get_spell_query (name on TBC, id elsewhere) + api.get_family_spell_id_state (resolved/absent/unresolved, so "could not answer" no longer latches false); truth pass vs classic_era/anniversary/titan/forever/live cited; compat.lua + smoke.lua + secret_guard_state.lua only; 40/0, luacheck 2/0, 11/11 muts (bench/f4_family_spell_id_2026-10-19.md) | done | ses_ea97ceaa6ffeWHYdLP9XZzl0s9 |
| docs-auditwave | final release-docs truth pass: CHANGELOG [2.1.1] "Audit-fix wave" section (2 HIGH + 4 MEDIUM, citation per finding) + 2 corrections to earlier passes (the druid "states none" hold line; the paladin's 2-row pre-pull table → 11 rows / 17 rotation rows / 12 guide slots / 14 HUD slots); TESTING.md 4 new checks (druid press-nothing hold, logout persistence, mid-session reset, paladin strip per family) + the druid-hold line corrected; README's blanket pre-pull-drill claim corrected (warrior/hunter/rogue grade the utility rows, paladin grades the seal, druid/shaman citations only); live script extended in place (§1.9, §5.6, §7.11 + reload caveat, §7.12, P10 rows, §10 report-back) | done | — (desk `docs-auditwave`; session id not available to the desk — orchestrator to fill) |
| range-api-matrix | READ-ONLY: client-API matrix for the range fix (which range APIs exist per family, which are protected) — bench/briefs/brief_range-api-matrix_2026-10-21.md; desk `range-api-matrix`; filed by the orchestrator (the desk had NO write tool): bench/range_api_matrix_2026-10-21.md + desk journal + done signal | done — classic_era source facts CONFIRMED (C_SpellBook.IsSpellBookItemInRange absent from the classic source; one C_Spell.IsSpellInRange callsite CooldownViewer.lua:713; the client ships the protected-function MECHANISM but NO list naming any protected API); web = CONTEXT ONLY; 3 open follow-ups (FU-1/FU-2/FU-3) + 7 gaps; it CORRECTED the orchestrator matrix row "legacy global exists nowhere" -> "not in FrameXML, binary presence UNCONFIRMED (FU-2)" | ses_ea1775d2bffeozVeLnBY5WeLNv |
| design-mode-ux | designmode.lua + tests/designmode_state.lua ONLY: options panel usable in design mode, design visuals above it, closing options keeps design mode, new control frame with a LOCK button — bench/briefs/brief_design-mode-ux_2026-10-21.md; desk `design-mode-ux` | running | ses_ea1775d2affe0oL1dUYK72EUHg |
| range-lrc-guard | the range fix in the vendored LRC: never call the blocked item-range API, fall back to the interact bands where the spell-range API cannot answer (R3 modern-spell path DEFERRED — operator declined the in-client probe) — bench/briefs/brief_range-lrc-guard_2026-10-21.md; desk `range-lrc-guard`; owns Libs/LibRangeCheck-2.0 + tests/lrc_guard_state.lua only | done — R1+R2 then R7 (uniform ladder on ALL five families, zero client range calls); lrc_guard_state 59->170 checks; harness 43/0, luacheck 2/0; 7/7 muts killed; bench/range_lrc_guard_2026-10-21.md; DEPLOYED | ses_ea17523ffffeey7UIT6JOn0aSR |
| design-mode-ux | designmode.lua + tests/designmode_state.lua ONLY: options panel usable in design mode, design visuals above it, closing options keeps design mode, new control frame with a LOCK button — bench/briefs/brief_design-mode-ux_2026-10-21.md; desk `design-mode-ux` | done — CHROME strata contract (panel 100 < veil 110 < visuals 130 < guides 140 < control 150), input overlays BELOW the panel (FULLSCREEN), mouse-transparent full-screen frames, Esc/options-window sync + OnHide backstop, session-only Lock/Exit control panel (no db key); designmode_state 512->655 checks; harness 43/0, luacheck 2/0; 16/16 muts killed; bench/design_mode_ux_2026-10-21.md; DEPLOYED | ses_ea1775d2affe0oL1dUYK72EUHg |
| range-family-correct | NOT DISPATCHED — the range NUMBERS are the lib's hardcoded modern-client interact table (8/28 yd), so Era/Anniversary are approximate and the operator flagged it ("era inspect range is different"). Three candidate semantics (family-correct band / exact yards / keep uniform) + the trade-offs are written up; the operator was asked and did not answer, so the standing rule keeps the shipped (c) uniform band. brief: bench/briefs/brief_range-family-correct_2026-10-21.md | queued (awaiting operator gate) | — |
| class-activation | the operator's order (2026-10-21): only the SELECTED class's module executes, the selection is an OPTIONS dropdown (Auto = your class, default; + the six class names); the class files register their body as a loader, main.lua activates the selected one at init, the other five stay EMPTY — brief bench/briefs/brief_class-activation_2026-10-21.md; desk `class-activation` | **DONE + orchestrator-verified.** A1: classes/rogue.lua wraps its body as `st.class_loaders["ROGUE"]` (two edits, body unchanged); main.lua:641 `ST:activate_class()` (Auto->playing class / explicit pick, pcall, class-table rollback, one notice, idempotent) called from init_libs before `interfaces_are_initialised`; option `class_activation` (Auto + six, default "Auto" in ST.class_defaults, widget option_tables.lua:199). A2: the other five wrapped the same way; NEW tests/class_activation_state.lua (70 checks: all six load with EMPTY tables, Auto->playing class, explicit pick, throwing loader fails closed, the playing class does NOT activate when another is selected); tests/toc_check.lua's 200-local guard fixed to measure the max prototype count (it had gone blind on the wrapper: druid 180, hunter 166, paladin 182, rogue 71, shaman 176, warrior 178). Orchestrator added the run.sh line. Harness 44/0, luacheck 2/0 in 86 files, 11/11 muts | ses_ea10e1f72ffeI989yUe3oXSFBF |
| class-isolation-shared | the operator's order (2026-10-21): "no class features so cross each other. each class must use their own functions" — brief bench/briefs/brief_class-isolation-shared_2026-10-21.md; desk `class-isolation-shared` | **DONE + orchestrator-verified.** ONE provider contract per class (`ST.<CLASS>.practice_panel`: drill key/order/labels/session seams/progress); shared layer asks `ST[ST.active_class]` only — the four hardcoded practice_ui routes + drill-key literals moved into the class modules, `ST.PALADIN.get_rotation_key` + the seal/twist design descriptors moved into classes/paladin.lua (shared registry gained generic `DM.register_element`), `main.lua` records `self.active_class`. NEW machine-enforced guard in tests/wiring_check.lua §10 (comment-blind: fails on any `ST.<CLASS>` in shared executable code; pins active-class keying). Harness 44/0, luacheck 2/0 in 86 files, 11/11 muts (orchestrator re-ran M1 independently on a /tmp copy: injected `ST.HUNTER` -> the exact expected FAIL). bench/class_isolation_2026-10-21.md. Filed residuals: `ui.build_hunter_report`/`ui.build_warrior_execute_report` stay shared (no class-table coupling — natural follow-up); non-practice `player_class` branches in main.lua out of lane scope | ses_ea0d2c9c1ffev71h4dcciylSi1 |
| deploy-tool | tools/deploy.sh — the orchestrator's overreach (the copy is the OPERATOR's job): written, then DELETED on the operator's objection the same day | withdrawn | — |
| compat-tbc-defects | compat.lua + NEW tests/spell_known_state.lua ONLY: (1) DELETE `api.CheckInteractDistance` + its rawget (protected on TBC Anniversary — ADDON_ACTION_BLOCKED, operator in-client 2026-10-21; standing zero-client-range-calls policy); (2) `api.is_spell_known_state` must never throw — accept number|string, resolve names to numeric ids, pcall every probe, skip throwers, unknown => false,"unknown" (`IsSpellKnown("Kill Shot")` -> deprecated shim -> `C_SpellBook.IsSpellInSpellBook(string)` throw killed the hunter post_init) — bench/briefs/brief_compat-tbc-defects_2026-10-21.md; desk `compat-tbc-defects` | **running** | ses_e9f8d9783ffexJE4rS06g20dTM |
| range-engine-tbc | main.lua (range state from `api.UnitDistance` exact yards; melee 5 / ranged 30-35; floor/ceil band + `ST.target_distance`; works with LRC absent; class `post_init` guarded), hunter_ui.lua (sweet-spot from yards; per-subfeature `st.guard.run` isolation so one feature cannot quarantine the class hook), vendored LibRangeCheck (build NO interact checkers; zero protected calls), NEW tests/range_source_state.lua + the suites pinning the old checker source — bench/briefs/brief_range-engine-tbc_2026-10-21.md; desk `range-engine-tbc` | **running** | ses_e9f8d9782ffeP0byqWMW6xPmFv |
| lazy-bars | **operator order 2026-10-21**: "make sure bars like oh do not load unless user is using it" — clarified: SWING bars only (mainhand/off-hand/ranged), gate = **enabled AND in use** (no off-hand frames without an off-hand weapon, no ranged frames without a ranged weapon, no frames for an option-disabled bar; built lazily via one idempotent `ST:ensure_bar(hand)` on first need, never destroyed, every getter nil-safe) — bench/briefs/brief_lazy-bars_2026-10-21.md; desk `lazy-bars` | queued — **blocked on main.lua**: dispatch only after range-engine-tbc lands + reconciles (disjoint from bars.lua until then) | — |
| swing-wire-hunter | read-only defect hunt: why mh/oh/ranged are dead on every class (vendored-lib wire vs SuperSwingTimer direct-CLEU vs Blizzard reference; Era / TBC-Anniversary / Retail-Forever) — bench/briefs/brief_swing-wire-hunter_2026-10-22.md; desk `swing-wire-hunter` | done (report filed as desk journal + done signal 20261022T003739Z; 7 findings D1-D7, close-outs U1-U8; orchestrator-verified every citation, closed U4 via origin/forever) | deleg_e944edf9 / sa-0-1ac963b8 |
| swing-wire-build | OUR-files fixes only: D3 idle nil-shape + :331 comment, B2 probe-gated WEAPON_SLOT_CHANGED, B3 optional unit filter (`swing_source.lua` + `tests/swing_source_state.lua`; Libs/TOCs/run.sh/main.lua/bars.lua off-limits, FILE-don't-touch) — bench/briefs/brief_swing-wire-build_2026-10-22.md; desk `swing-wire-build` | done (report + desk journal + done signal 20261022T004500Z; diff verified 2 files, CRLF kept, stray luac.out removed; awaiting proctor verdict) | deleg_fb295452 / sa-0-66bc3e14 |
| swing-wire-proctor | independent read-only verdict on the build (B1/B2/B3 logic, pins, scope, standing rules; harness/luacheck/mutations UNVERIFIED on that seat, orchestrator closes) — bench/briefs/brief_swing-wire-proctor_2026-10-22.md; desk `swing-wire-proctor` | done PASS (report filed as desk journal + done signal 20261022T005000Z; one low pin-gap F1; orchestrator-closed executions: run.sh 46/0, suite 149 PASS by direct run, luacheck 2/0) | deleg_4b60d91a / sa-0-835d3001 |
| swing-wire-hunt2 | post-strip Era/Anniversary still-dead hunt (loadedAddonName gate, deadline ordering, init gates, registry delivery, bar-side death, SST contrast) + REAL-lib harness spec — bench/briefs/brief_swing-wire-hunt2_2026-10-22.md; desk `swing-wire-hunt2` | done (report filed as desk journal + done signal 20261022T010000Z; Era all-hops-WIRED, Anniversary WIRED-except-D2-ranged, new D8 deadline-trap + D10 stale-copy ranking + HU-25 harness spec; orchestrator closed U-H2/U-H4/U-H5 branch halves) | deleg_f6face31 / sa-0-0201288b |
| swing-wire-fix | HU-25 real-lib harness (red first on D8/D2 legs) + D8 deadline rewire in main.lua narrow regions (new suite + :382-386/:393-411/:770-777; run.sh/TOCs/Libs/bars/compat/classes/swing_source/diag off-limits) — bench/briefs/brief_swing-wire-fix_2026-10-22.md; desk `swing-wire-fix` | done (report + desk journal + done signal 20261022T011500Z; red 109/14 recorded pre-fix → green 112/0 + 1 expected-fail; orchestrator added the run.sh line, full harness 47/0 incl. real_wire PASS, luacheck 2/0; awaiting proctor verdict) | deleg_29dcd1f0 / sa-0-3bc11bfe |
| swing-wire-proctor2 | independent read-only verdict on harness + rewire (assembly reality, leg entailment, three main.lua regions, scope, standing; executions UNVERIFIED on that seat, orchestrator closes) — bench/briefs/brief_swing-wire-proctor2_2026-10-22.md; desk `swing-wire-proctor2` | done PASS, no findings (report filed as desk journal + done signal 20261022T012500Z; orchestrator-closed: run.sh 47/0, suite PASS, luacheck 2/0, rewire-detached mutation re-run → exact 14-fail red reproduced, copy removed) | deleg_4eaceee9 / sa-0-9b3708f1 |

## Reconcile decisions (2026-10-21, TBC Hunter test-session wave)
- **The interact-band ladder is DEAD — it was the same mistake moved one call sideways.** The
  2026-10-21 in-client log (TBC Anniversary, HUNTER) is `ADDON_ACTION_BLOCKED ... protected
  function 'check_interact_distance()'` via `compat.lua:954` <- `hunter_ui.lua:877` <-
  `hunter_ui.lua:1510` <- `classes/hunter.lua:909` <- `guard.lua:178` <- `bars.lua:693`, and
  the same protected function is reached from the vendored LibRangeCheck's interact checkers.
  The earlier fix (blocked `IsItemInRange` -> interact bands) swapped one protected call for
  another. **The only permitted distance source is now `api.UnitDistance` (exact yards from
  unprotected `UnitDistanceSquared`); no protected range/inspect call on ANY family.**
  `CheckInteractDistance` is removed from compat and from the vendored library.
- **The cascade is its own defect.** `rf_update` disables range checking after 3 poll failures
  (~0.15 s) -> no range state, no distance bar; and `guard.run`'s 25-throw quarantine kills the
  WHOLE `class:HUNTER:on_bar_update` site when one optional sub-feature (the range helper)
  throws every frame -> "the bar came up but nothing happened, then they stopped working".
  Fix: per-subfeature guard sites in `hunter_ui.update` + the class `post_init` guarded in
  main.lua. A class module must never be able to abort addon init.
- **`is_spell_known` must be throw-proof.** The hunter deliberately passes a spell NAME on TBC
  (old clients' `IsSpellKnown` took names) but this client's deprecated global forwards to the
  numeric-only `C_SpellBook.IsSpellInSpellBook` -> throw -> hunter `post_init` aborted unguarded
  (`main.lua:830` <- `main.lua:712`). Root-cause fix in compat (name -> id, pcall every probe).
- **Superseded:** the queued `range-family-correct` row (operator never picked a semantic). The
  client has now picked for us: exact yards. That brief is obsolete; the range-engine-tbc brief
  replaces it.
- **Filed risk, not fixed in this wave: `api.IsSpellInRange` (every class's range helper).**
  Verified on the `classic_anniversary` branch: no global `IsSpellInRange` doc entry exists, so
  compat resolves to `C_Spell.IsSpellInRange` (`SpellDocumentation.lua:601`; Blizzard's own
  insecure `Blizzard_CooldownViewer/CooldownViewer.lua:713` calls it). Whether the client also
  blocks it for tainted addon code is UNVERIFIED — Blizzard's call site proves only that the API
  exists, not that addons may call it. The operator's 2026-10-21 log names only
  `check_interact_distance`, so no evidence of a block. The per-subfeature guard isolation
  (range-engine-tbc R3) bounds the blast radius if it ever blocks; the in-client checklist must
  ask for the log if a new ADDON_ACTION_BLOCKED names `is_spell_in_range` /
  `C_Spell.IsSpellInRange`. Do NOT pre-emptively strip the class range helpers on a hypothesis.

## Reconcile decisions (2026-10-21, operator test-session wave)
- **A lane that dies silently is recorded as DEAD, not done.** The first dispatch of the
  class-activation brief (session `ses_ea125e3e7ffe4wwjDah066K1ce`) ended in a task error
  with no text result, no desk, no bench file and NO file changes — verified by inspecting
  the tree, not by trusting the completion notice. Cause (probable, not proven): one agent
  asked to hold six 200 KB class files plus six 200 KB suites in context. Fix: the work is
  SPLIT (A1 = mechanism + the rogue class, 7 files; A2 = the other five classes + the proof
  suite), and every brief now carries the context-discipline rule: never read a whole class
  file or suite, use targeted greps and surgical patches.
- **The operator owns the client copy.** The orchestrator's `tools/deploy.sh` was written and
  then DELETED on the operator's objection ("that is my job, not yours"); the orchestrator
  writes nothing into the game folder from now on and hands the operator a copy list.
- **The six "Error loading classes/*.lua" warnings were a DEPLOYMENT gap, not a code bug.**
  Evidence: the client's own log `/home/sam/Games/batttlenet2/drive_c/Program Files (x86)/World of
  Warcraft/_classic_era_/Logs/FrameXML.log` (2026-10-21 08:34) carries the six TOC lines and NO Lua
  error text; the deployed addon folder had NO `classes/` directory, while every other deployed file is
  byte-identical to the repo. The orchestrator copied `classes/*.lua` into the deployed folder
  (2026-10-21 08:54, six files verified byte-identical). The class modules are listed in EVERY flavor
  TOC BY DESIGN (AGENTS.md: a class module missing from a TOC does not load on that client) and each
  module only activates for its own class — "only my class should load" is NOT the shipped contract;
  the practice engine resolves the PLAYER's class module (`practice.lua:3421 H.practice_class_module`),
  and the broken practice the operator saw is the missing deployment, not a per-class load.
- **ADDON_ACTION_BLOCKED = the vendored LRC's ITEM range checker.** `LibRangeCheck-2.0.lua:498` calls
  `IsItemInRange(item, unit)`; the lib resolves it at line 422 as `(C_Item and C_Item.IsItemInRange) or
  _G.IsItemInRange`, and on classic_era the legacy global IS `C_Item.IsItemInRange`
  (`Blizzard_DeprecatedItemScript/Deprecated_ItemScript.lua:29`). The call is blocked by the client
  (not a catchable Lua error → the addon's pcall cannot suppress it). NO legacy `IsSpellInRange` global
  exists on ANY of the five target branches, so the LRC's spell checkers are dead everywhere; the
  interact-distance checkers DO work (the melee checker at main.lua:1791 ran unblocked). Fix lane
  `range-lrc-guard` queued: the ladder falls back to the interact bands when the client's range API
  cannot answer, and the item checker never calls the blocked API.
- **Operator warning (2026-10-21): a read-only lane cannot cross-client check wow-ui-source.** The
  hunter desk has no shell; ast_grep sees only the CHECKED-OUT `classic_era` branch. So its report is
  classic_era + web CONTEXT only, and every branch-specific claim must carry its branch. The
  orchestrator closed the cross-branch facts with shell and filed them as
  `bench/range_api_orchestrator_matrix_2026-10-21.md` (per-branch presence of C_Spell.IsSpellInRange,
  the legacy IsSpellInRange global, C_SpellBook.IsSpellBookItemInRange, the legacy IsItemInRange
  global, and CheckInteractDistance). Both running lanes were steered to cite that file instead of
  guessing. **Rule for the next wave: any cross-client claim from a no-shell lane is a hypothesis
  until the orchestrator re-checks it with `git -C /home/sam/wow-ui-source grep <branch>`.**
- **Design mode vs the options panel — the mechanisms are now proven, not guessed**
  (`bench/design_mode_client_facts_2026-10-21.md`): the options panel is the AceGUI Frame container at
  strata FULLSCREEN_DIALOG / level 100, the design layer is at BACKGROUND and the guides at DIALOG
  (so the design visuals are BEHIND the panel — the operator's report #2); the panel's title drag only
  ends in the title's own mouse-up, so a design-owned mouse-enabled frame over the title bar can leave
  it stuck mid-drag (report #1); the options panel is NOT in UISpecialFrames while the design layer IS
  (designmode.lua:254), so Esc hides the design layer -> OnHide -> DM.stop(true) ends design mode
  while the panel stays open (report #3).

## Operator in-client confirmations
- 2026-10-21 operator test session (Classic Era): the six "Error loading classes/*.lua" warnings = the deployed addon had no `classes/` folder (orchestrator deployed it; the operator copies the files over by hand for each test, so the orchestrator deploys changed files after each wave).
- 2026-10-21 operator: the C_Spell.IsSpellInRange in-client probe was DECLINED ("i have to copy all files over. so use a test, like we always do.") -> the modern spell-range path stays UNCONFIRMED and UNUSED; the shipped range ladder is the interact-band fallback (8 yd / 28 yd). The accurate per-class range is an OPEN follow-up needing one in-client confirmation (the exact command is in bench/range_lrc_guard_2026-10-21.md when it lands).
- 2026-10-21 operator: playing ROGUE on Classic Era (the range fix is client-wide, not class-specific).
- Blood Frenzy rune 412507 CONFIRMED in-game by operator 2026-10-19 (shaman follow-up consumer).
- Sniper ranks per operator 2026-10-19: 85/86/87 endings (1310785/1310786/1310787); rank↔id mapping still UNCONFIRMED — in-client GetSpellInfo owed.
- Hawk ranks per operator: R2 1293525 / R3 1293526 / R4 1293527 (R1 1293241); plus two distinct Summon Hawk spells 1293248 + 1312639 (wowhead forever pages, operator-linked). U2 probe still open.
- Molten Blast 425339 CONFIRMED via classic.warcraftdb.com (matches sim id). Lava Lash 408507 CONFIRMED via same.
- Envenom 399963: wowhead classic page EXISTS (operator link); Rune of Venom item = 210322. Still needs in-client GetSpellInfo — latch stays frozen, no code change on web evidence alone.
- Stormstrike 6s CD on SoD CONFIRMED by operator.
- SoD-vs-Era gating principle CONFIRMED by operator: same client, different games — gate on rune knowledge, never client version (matches sod-detect mechanism).

## Reconcile decisions (2026-10-19, figure-out wave)
- Operator: W2 Battle Shout = BUILD IT FULLY. Victory Rush = SKIP (already inert-by-default; HOLD DORMANT stands).
- Operator: H2 hunter lust branch = CUT (sim-faithful, best for practice). NOTE (operator order): keep the door open — a conservative-playstyle alternative may return later as an opt-in toggle. H2-cut lane dispatches after the hunter-badges lane lands (same files).

## Reconcile decisions (2026-10-19, rotation-fix wave)
- Mid-wave harness reds were all parallel-writer crossfire (each lane's own suites green, others' files mid-edit). Final orchestrator run on the landed tree: 37/0, luacheck 2/0.
- Follow-ups banked in lane journals (options wiring, sensors, W2, hamstring slot, SoD detection): next build wave, not this one.
- Warrior audit file was truncated mid-G1 on disk; lane rebuilt from its desk journal + re-verified every claim against fresh sim + wowhead sources before editing. Gap list stands on the re-verification, not the memory.

## Reconcile decisions (2026-10-19, parity wave)
- D1 hunter hook order: five-class lane verified independent frames, no functional issue — closed as documented behavior, no change.
- F3 stands accepted; F6 pin landed (BOGUS→eviscerate); F1/F2/F4/F5 closed with pins + 8/8 mutations.
- Change of default (red SS zone ON): owner-ordered, gate recorded in code + journal. Standing rule otherwise holds.

## Rules every lane carries
No git. No lint-config changes. Warning wiring per wire-not-strip (trace → WIRE / REMOVE-with-rationale / KEEP-with-rationale; never `_`). Whitespace fixes only inside touched lines. Endings preserved. Harness + mutation proofs on /tmp/opencode copies. New toggles: nil-safe reads, defaults documented; no default-visible change without an explicit gate.

## Direct fix (2026-10-21, orchestrator): swing-engine wire misalignment
- Operator report (TBC hunter, in-client): steady cast bar works, auto shot does
  not, ranged bar dead, no error. Root cause: the vendored classic library
  re-fires UNIT_SWING_TIMER_* as SWING_TIMER_* WITH the unit id leading, while
  swing_source fires speed-first; the app's handlers take speed-first. The
  dispatcher passed the unit id through, so every classic START/UPDATE/STOP
  misaligned by one argument, hit the unknown-hand guard (one notice, then
  silence), and the bars rendered their init seed once and froze.
- Fix (main.lua only, no lib/handler-signature changes): callback_event_handler
  drops a leading "player"/"target" token on SWING_TIMER_* events; Forever
  payloads (speed first) pass through intact. Plus per-hand START/UPDATE/STOP
  receipt counters (note_swing_wire) surfaced in /st diag (swing_<hand>=s/u/p,
  swing_last=KIND:hand:age) so a quiet engine is visible.
- Proof: tests/main_init_state.lua §14b (972 checks) pins both engines' exact wire
  shapes through the dispatcher plus the diag line. M1 (strip neutered) and M2
  (over-strip any-string, eats Forever's hand-only STOP) both fail on /tmp/opencode
  copies. Harness 46/0, luacheck 2/0 in 88 files.
- In-client owed: hunter auto-shot cycle advances the ranged bar; /st diag shows
  swing_ranged counts climbing.

## Direct fix (2026-10-21, orchestrator): options comparator crash
- Operator report (TBC, /st options open): option_tables.lua:219 "attempt to
  compare table with nil" via AceConfigDialog FeedGroup. Root cause: the
  class_activation select's `sorting` was written as a two-arg comparator, but
  AceConfigDialog calls sorting with just the info table (it must RETURN the
  ordered key array). So it compared (info, nil) and threw on open.
- Fix: literal array { "Auto", "DRUID", ... } (the file's own convention, cf.
  show_bar_conditions_sorting). Only select with a function sorting in the tree.
- Proof: options_load_state.lua walker now resolves every select's sorting the
  way FeedGroup does (call-with-info, array back, keys covered both ways) plus a
  targeted Auto-first order pin. Comparator restored on a /tmp/opencode copy
  fails with the exact production error on every class walk. Harness 46/0,
  luacheck 2/0.

## Direct fix follow-up (2026-10-21, orchestrator): login unknown-hand notice
- Operator report: "unknown hand" chat notice at login, before combat; Era and
  Anniversary do not behave the same. Mechanism: that notice prints only when a
  swing payload arrives misaligned (hand slot holding a non-hand). With the
  pre-strip main.lua, login's UNIT_ATTACK_SPEED reports arrive unit-first and
  trip it once, then silence. If the client's main.lua predates the strip (or
  the fix went to the other client's AddOns folder - Era and Anniversary are
  separate folders), the notice persists and the ranged bar stays dead.
- Era vs Anniversary, verified from the vendored lib (no guessing): wire shapes
  identical (zero Fire calls inside the version branches; the legacy re-fire is
  unconditional). Ranged DRIVERS differ: Era additionally uses SPELL_CAST_START
  and FAILED_QUIET paths (isClassic-only); Anniversary relies solely on
  SUCCEEDED(75) + START_AUTOREPEAT. Spell tables are per-version; no matching
  branch = empty tables, no error, melee survives, ranged does not.
- Change (read-only): /st diag now prints proj=/exp=/bcc= (WOW_PROJECT_ID,
  LE_EXPANSION_LEVEL_CURRENT, WOW_PROJECT_BURNING_CRUSADE_CLASSIC) - exactly
  what the lib's isBCC test reads. Pins in §14b. M1 re-verified on a fresh
  /tmp/opencode copy (2 FAILs). Harness 46/0, luacheck 2/0.
- Owed in-client: /st diag line (tells us whether the fix is live AND what the
  lib sees on that client).

## Session close (2026-10-21, operator)
- Operator closed the session. Honest state: the swing-wire dispatcher fix and
  the options-panel comparator fix are landed and offline-proven (harness
  46/0, luacheck 2/0, three mutation proofs); NOTHING is in-client proven,
  because none of the fixes had been copied to a client when the session
  ended. The ranged bar on TBC Anniversary is UNPROVEN, not fixed.
- The vendored swing lib is canonical (v32, byte-identical to the operator's
  paste) and is used for every classic-line client; the only non-lib engine
  is swing_source on WoW Forever. The next session's first job is a harness
  with the REAL lib in the loop (the current suites stub it, which is how the
  wire defect survived).
- Unreconciled in the tree: the range-engine-tbc lane's files (main.lua,
  hunter_ui.lua, vendored LibRangeCheck) — the lane died on a rate limit
  after writing them; suite green, diff not re-read by the orchestrator.
- Full status: bench/swing_wire_status_2026-10-21.md.

## Workshop docs filled out (2026-10-21, orchestrator, operator order)
- `workshop.md`: added the "where the state lives" pointer block (journal = lane
  ledger, hands-up = escalations, bench = briefs/findings/lessons, the session
  status file, CAIRN = disposition / AGENTS = mechanics), a `README.md` room row
  (the repo map), step 7 of the flow (the operator copies into the client; an
  uncopied fix is not a fix), the desk snapshot now carries `range-engine-tbc`
  (221 desks), and lessons 11-15: the stubbed engine hides the engine's wire;
  a dispatcher that shifts one argument takes EVERY bar with it (mainhand and
  offhand dead for every class, per the operator's finding); the options
  `sorting` member is a key array, not a comparator; the operator's folder is
  the client; desk the code.
- `hands-up.md`: HU-25 rewritten to the operator's scope (no swing bar works —
  every hand, every class; fixes are offline-proven only and the suites stub
  the engine) with the decision "real-lib harness first, or in-client first";
  HU-27 open (the range-engine-tbc lane's files are in the tree unreconciled —
  the lane died on a rate limit after writing them); HU-28 open (the shipped
  registry decides the payload shape: the TOC ships CallbackHandler v7 while
  the lib bundles v8 — ship the bundled v8, or keep v7 and let the harness
  prove the client shape?); HU-26 resolved (operator correction: code fixes go
  through a desk; the orchestrator briefs, dispatches and reconciles).

## Reconcile decisions (2026-10-22, swing-wire-hunter)
- Hunter lane DONE (deleg_e944edf9): 7 findings filed as
  `desks/swing-wire-hunter/journal.md` + done signal. Orchestrator
  re-verified every cited file:line; closed U4 via
  `git show origin/forever` (Blizzard manager handles
  `WEAPON_SLOT_CHANGED`/`PLAYER_TARGET_CHANGED`/`PLAYER_SWING_RANGE_UPDATE`;
  `swing_source` lacks all three). U2 tree half: Anniversary project id 5
  CONFIRMED on `origin/classic_anniversary`; expansion-level half is
  binary-provided — in-client diag only.
- Split: builder lane `swing-wire-build` owns the OUR-files items only
  (D3 idle nil-shape + B2 equip-change handling + :331 comment;
  `swing_source.lua` + `tests/swing_source_state.lua` — no owner conflict).
  D2/D4/D5/D6 are vendored-lib → HU-29 (operator: upstream / fork-patch /
  accept). `Libs/` stays untouched until ruled. U1/U2/U3/U7 go on the
  operator's in-client copy list once the builder lands.

## Reconcile decisions (2026-10-22, swing-wire-build + proctor)
- Build card: proctor verdict PASS (`desks/swing-wire-proctor/journal.md`,
  done signal 20261022T005000Z). Card complete minus the operator's
  approval/copy — nothing here is in-client proven.
- F1 (fallback-branch pin never exercised, sandbox-only: real frames
  always offer `RegisterUnitEvent`) ACCEPTED as residual, not a rebuild:
  proctor graded it low and non-blocking; the required B3 pins are present
  and traced. Revisit only if the fallback ever fires in-client.
- Orchestrator-closed executions on the final tree: `bash tests/run.sh`
  46/0, `swing_source_state.lua` 149 PASS (direct run), luacheck 2/0 in
  88 files, CRLF intact, diff confined to the two owned files.
- Copy list for the operator: `swing_source.lua`,
  `tests/swing_source_state.lua` (offline only), `main.lua`,
  `option_tables.lua` (2026-10-21 fixes, never copied). In-client
  checklist: U1 (Era mh / Anniversary ranged advance + `/st diag`
  `swing_<hand>` counts), U2 (`proj=/exp=/bcc=` on Anniversary), U3
  (`UnitRangedDamage` shape on 2.5.6), U7 (Cata/Mists "engine offline"
  eyeball), D1 confirmation the strip holds live.

## Reconcile decisions (2026-10-22, swing-wire-fix + proctor2)
- Fix card: proctor verdict PASS with NO findings
  (`desks/swing-wire-proctor2/journal.md`, done signal 20261022T012500Z).
  Card complete minus the operator's approval/copy — nothing here is
  in-client proven, per operator rule nothing is called fixed.
- What the tree now proves offline (real lib + real registry + real
  dispatcher in the loop): happy legs green on Era and Anniversary(1)
  profiles (strip + wire shape hold with the real engine); D8 negative
  leg red pre-fix → green post-fix; Anniversary-`nil` leg xfail-marked
  for HU-29. Orchestrator independently re-ran the rewire-detached
  mutation → the exact 14-failure red reproduced.
- Orchestrator-closed executions on the final tree: `bash tests/run.sh`
  47/0 (incl. `real_wire_state` PASS), luacheck 2/0 in 89 files, CRLF
  intact, diff confined to `tests/real_wire_state.lua` (new) + the three
  `main.lua` regions + ledgers/briefs/`run.sh` line. `Libs/` untouched.
- Copy list additions: `main.lua` (strip + D8 rewire),
  `tests/real_wire_state.lua` (offline only). U-H8 (strip-in-folders)
  still needs the operator's folder; D10 ranking stands until a session
  with diag output says otherwise.

## Dispatch (2026-10-22, orchestrator): swing start/end/reset + test-gap audits
- Hunter lane ses_e9b191e5cffeLWGAXiIHVJPd9A: read-only CLEU start/end/reset audit (ranged .5s hidden-cast, mh/oh never showing, steady/auto interference; Era/TBC/Retail/Forever; SuperSwingTimer-WoW reference). No write scope.
- Proctor lane ses_e9b191e1effeom76gncvku9wnM: read-only suite-gap audit (real_wire_state, main_init_state §14b, swing_source_state, run.sh; stub-vs-real registry coverage per hand per family). No write scope.
- Builder lane waits on both findings (dependency); orchestrator reconciles + runs full suite.

## Proctor gap audit filed (2026-10-22, orchestrator)
- Lane ses_e9b191e1effeom76gncvku9wnM (read-only, no write scope) complete.
  Report filed as bench/proctor_swing_gap_2026-10-22.md (orchestrator-verified:
  every checkable claim re-checked against the tree — offhand undriven,
  FAILED_QUIET/CAST_START/MISSED/PARRY/EXTRA_ATTACK absent from real_wire,
  §14b direct-dispatch, swing_source fake registry, no swing_engine_state
  suite; all hold).
- Top-3 pins for the builder brief, in order: (1) TBC ranged driver table
  through real lib + real v7 (SUCCEEDED-without-autorepeat, CAST_START and
  FAILED_QUIET negatives per family); (2) full START->UPDATE->hand-only STOP
  lifecycle per hand incl. offhand (needs two-speed fixture + clock advance);
  (3) MISSED routing + PARRY/EXTRA_ATTACKS as xfail pending HU-29.
- Hunter lane ses_e9b191e5cffeLWGAXiIHVJPd9A still running; builder brief waits
  on it (dependency) then carries pins 1-3.

## Ruling + dispatch (2026-10-22, orchestrator, operator order)
- Hunter lane ses_e9b191e5cffeLWGAXiIHVJPd9A CANCELLED mid-flight per operator:
  read-only seats (hunter/proctor: no shell, no cross-client branch reads)
  must not own cross-client verification — their branch claims come back
  UNVERIFIED and risk new bugs. Recorded as resolved HU-30.
- Proctor lane ses_e9b191e1effeom76gncvku9wnM completed and filed as
  bench/proctor_swing_gap_2026-10-22.md, but its cross-client statements
  carry the seat's own UNVERIFIED caveat — usable as a pin list (Pins 1-3),
  not as API truth.
- New lane: desks/swing-cross-client/ (shell-capable seat), brief
  bench/briefs/brief_swing-cross-client_2026-10-22.md. Write scope:
  main.lua dispatcher region + named swing-state lines in bars.lua /
  classes/hunter.lua / hunter_ui.lua + tests/real_wire_state.lua legs.
  run.sh wiring stays orchestrator-owned.
- Cross-client lane session: ses_e9b153168ffeZ53a0otTtWqCbV (desk swing-cross-client).

## Cross-client lane cancelled, zero output (2026-10-22)
- Lane ses_e9b153168ffeZ53a0otTtWqCbV cancelled before its seat wrote
  anything: desk journal untouched since dispatch, no signals, and no product
  file changed by it (tree diff unchanged from before dispatch).
- Honest answer to the operator's "why take 10 hours": the time was not work
  — the seat never began. Nothing to reconcile, nothing to revert.
- Standing state: the verified pin list is
  bench/proctor_swing_gap_2026-10-22.md (Pins 1-3); the brief is
  bench/briefs/brief_swing-cross-client_2026-10-22.md; both await the
  operator's call on how to proceed.

## Parallel dispatch (2026-10-22, orchestrator, operator order: finish now)
- Display lane ses_e9b0ee364ffez1Y1QmPOsCqJlH (desk swing-display): bars.lua +
  classes/hunter.lua + hunter_ui.lua — mh never shows, ranged wrong value,
  steady/auto poisoned by shared state.
- Engine lane ses_e9b0ee35affefEeVcg78oJFHKo (desk swing-engine-fix): main.lua
  dispatcher/init/registration + compat.lua family detect — mh START never
  lands, TBC fallback driver under both gate outcomes.
- Harness lane ses_e9b0ee35affddtAQ5gXVsr2H9v (desk swing-harness):
  swing_source.lua + tests/real_wire_state.lua legs (Pins 1-3).
- Scopes disjoint by file; run.sh + full suite stay orchestrator-owned.
  Issue stated first in every prompt; no hunter/proctor anywhere.

## CLEU defects confirmed in pasted lib (2026-10-22, orchestrator)
- Operator pasted LibClassicSwingTimerAPI v32; spot-checked against vendored:
  identical. Four lib-side facts, all verified by grep (lib file + line):
  (1) :397 catches all SWING_MISSED so the :415 PARRY arm is dead;
  (2) :257 getUnit re-checks player.id instead of target.id;
  (3) :456 + :772 ranged arms are isClassic-only (TBC = SUCCEEDED(75) only);
  (4) :46 isMists self-compares the constant. Lib stays untouched.
- Steered engine lane ses_e9b0ee35affefEeVcg78oJFHKo via task_message to route
  around them in our code (fallback driver, no parry/target reliance).

## Scope ruling HU-31 (2026-10-22, operator)
- Lib-driven swing must work on classic_era, classic_anniversary, titanforge.
  Retail/Forever use their own API (swing_source / inert stand-in) — no
  classic-lib fallback built for them. Steered engine + harness lanes;
  display lane unaffected.

## Display lane reconciled (2026-10-22, orchestrator)
- ses_e9b0ee364ffez1Y1QmPOsCqJlH DONE. Trail complete: desk journal current,
  done signal filed, bench/swing_display_2026-10-22.md (new file only).
- Claims verified, not trusted: hunter_state.lua re-run in-tree PASS (1744);
  scope respected (bars.lua, classes/hunter.lua, hunter_ui.lua,
  tests/hunter_guide_state.lua, tests/hunter_state.lua — main.lua diff is the
  engine lane's ongoing work); /tmp/opencode probe leftovers belong to
  running lanes, untouched.
- Accepted: ranged shared-state provenance fix + Auto Shot exclusion fallback
  (6/6 mutations kill, M4-M6 ad-hoc). mh visibility correctly NOT claimed
  (needs engine START). Open follow-ups: committed lazy-bars suite + run.sh
  line (queued lane), cast spark U4, in-client U1-U3.
- Engine lane steered to the display contract before wiring build points.
  Full run.sh waits on engine + harness lanes.

## Harness lane reconciled (2026-10-22, orchestrator)
- ses_e9b0ee35affddtAQ5gXVsr2H9v DONE. Trail complete: desk journal current,
  two signals filed, scope respected (new file tests/real_wire_state.lua
  only — untracked, no product edits; swing_source_state/run.sh diffs
  predate today's lanes).
- Claims verified, not trusted: real_wire_state.lua re-run in-tree 482/0
  (3 xfail PARRY/EXTRA/D2); swing_source_state.lua 149 PASS; luacheck 0/0.
- Accepted: Titanforge-shaped third profile (project 11/exp 2/iface 38002,
  unblocks U-W1); driver loops era/anniv/titan with family negatives;
  per-hand lifecycle incl. Wrath re-fire quirk; MISSED x3 + PX xfail;
  Retail silent leg (own-API); sandbox clock/notice fixes (test-only).
  Mutations M5/M8/M9/M10 kill as quoted.
- Flags: lane reports the file's top header comment "reverted by an unknown
  hand" mid-lane and rewrote it per HU-31 — no other lane owns that file
  today; noted, watching. Crossfire noted (main.lua/swing_source.lua moved
  underneath from the engine lane; legs pass against landed versions).
- Owed: in-client U2/U3/U-H5. Full run.sh waits on the engine lane.

## Engine lane reconciled, full suite mine (2026-10-22, orchestrator)
- ses_e9b0ee35affefEeVcg78oJFHKo DONE. Trail complete (journal, 4 signals,
  bench/swing_engine_fix_2026-10-22.md). Scope respected (main.lua only;
  compat correctly untouched — design already held). Claims verified:
  FULL bash tests/run.sh 47 steps 0 failed; luacheck 2/0 floor in 89 files.
- Accepted: ST:bring_up_hand(hand) + init/equip wiring to the display
  contract, nil-guards on show/hide/lock/unlock, warrior/rogue ranged
  re-cut (disabled→unbuilt per HU-22, equip-point proof). Mutations M5-M7.
- Notes: .vscode/settings.json diff is IDE-local paths, not lane output —
  left alone. Harness header-revert flag watched, no recurrence.
- Gap dispatched: ses_e9af06825ffegCcCag426PhxOM (desk lazy-bars) —
  option_tables per-hand setter → bring_up_hand + committed
  tests/bars_lazy_state.lua. run.sh line stays mine after it lands.

## Lazy-bars lane re-dispatched correctly (2026-10-22, orchestrator)
- Prior attempt ses_e9af06825ffegCcCag426PhxOM errored (step interrupted, no
  result); result retrieved to authorize retry per tool rule.
- New lane ses_e9aeefc40ffeUyxqteI5OOllBR (desk lazy-bars) with the four lane
  skills named explicitly in the prompt (@bench-read, @desk-open,
  @desk-journal, @signal-write + missing-skill reporting). Same write scope:
  option_tables per-hand setter → bring_up_hand + tests/bars_lazy_state.lua.

## Lazy-bars lane reconciled, wave complete (2026-10-22, orchestrator)
- Lane DONE with all four skills confirmed in its report. Verified: journal
  current, done signal filed, option_tables diff = setter + widget rewire
  only (loop mirrors pre-existing generic/text setters exactly), new suite
  tests/bars_lazy_state.lua 37/0 in-tree.
- run.sh line added by orchestrator (bars_lazy_state after bars_state).
  FULL harness: 48 steps, 0 failed; luacheck 2/0 floor in 90 files.
- All four writer lanes reconciled (display, engine, harness, lazy-bars);
  no lane owns anything further. Owed: operator copy + in-client proof.
- Copy carries the HU-27 unreconciled range-engine files too (disclosed in
  the handoff, not hidden).

## Verify lane dispatched (2026-10-22, orchestrator, operator order)
- Lane ses_e9ae7341bffeLmXSlnVEy276AZ (desk swing-verify), brief
  bench/briefs/brief_swing-verify_2026-10-22.md. Four lane skills explicit
  in prompt with missing-skill reporting.
- Operator correction recorded: ranged = FULL swing timer (0.5s is part of
  the cycle display, never the whole bar); mh/oh/ranged must sweep, stop,
  and reset perfectly. No other writer running — no scope conflicts.

## Correction to verify lane (2026-10-22, operator)
- The 0.5s Auto Shot cast window is Era AND Anniversary (both classic-line),
  not TBC-only. Steered ses_e9ae7341bffeLmXSlnVEy276AZ: cast-window asserts
  identical on Era/Anniversary, fallback driver serves both.

## Ruling HU-32 (2026-10-22, operator)
- Orchestrator touches journal, hands-up, workshop ONLY. Bench (briefs,
  reports, pins) is the lanes' workspace — brief context goes in the
  dispatch prompt, the lane files its own bench artifacts. Past bench
  writes by orchestrator stand as history, not precedent.

## Workshop + hands-up brought current (2026-10-22, orchestrator, operator order)
- hands-up.md: HU-25 rewritten (wave landed: real-wire 482/0, display/engine/
  lazy contracts, full 48/0; owed = operator copy + in-client proof; verify
  lane running); HU-27 refreshed (tree moved: strip, bring_up_hand, display
  contract, lazy setter — revert impossible, review-against-contracts only);
  HU-28 narrowed (v7 proven in-harness, v8 still unshipped; closer = /st diag
  after copy); HU-29 refreshed (dead PARRY + getUnit + :46 confirmed vs paste;
  xfail pins landed; ruling a/b/c still owed). HU-12/18/19/20/24 untouched.
- workshop.md: state pointer now the live journal (Oct-21 status file =
  history); flow step 1 per HU-32 (brief in prompt, lane files bench);
  snapshot re-verified 2026-10-22 (234 entries, 12 new swing/lazy desks);
  lessons 16 (full timer, not the window), 17 (cast window Era+Anniversary),
  18 (name the four skills; read-only never cross-client; hands off bench).

## Clock lane dispatched (2026-10-22, orchestrator, operator rule)
- Lane ses_e9ae0e644ffeFG8GGPpjzoSC3g (desk swing-clock): GetTimePreciseSec
  main / GetTime fallback-only. Scope: raw GetTime() in shipped code →
  st.api.get_time(); Libs + docs + run.sh + TOCs excluded. Four skills
  explicit. Orchestrator grep sized it (paladin/shaman/progress-ui/ldb/
  nextaction_ui candidates; Libs files noted out-of-scope, not touched).

## Queued (2026-10-22, operator order, runs after clock lane)
- CLEU-parity lane (desk swing-cleu-parity): SuperSwingTimer-WoW vs ours,
  event-by-event (CLEU subevents, unit events, autorepeat, FAILED_QUIET,
  equipment/combat enter-leave) — list anything SST handles that we drop,
  then fix our side (lib stays untouched). Starts after ses_e9ae0e644ffeFG8GGPpjzoSC3g
  completes (write-scope separation).

## Commit sequence (2026-10-22, operator order)
- Hold the commit until the clock lane (ses_e9ae0e644ffeFG8GGPpjzoSC3g)
  returns and is reconciled. Then: full run.sh + luacheck, commit the wave
  (exclude .vscode/settings.json + luac.out), then dispatch the CLEU-parity
  lane (desk swing-cleu-parity). No commit before that point.

## Docs updated for commit rule (2026-10-22, orchestrator, operator order)
- workshop.md flow gains step 8: reconciled waves commit promptly on operator
  order (exclusions: .vscode/, luac.out, /tmp); committing is not a bench
  touch. Pending sequence (journal 2026-10-22): clock-lane reconcile → full
  suite → commit → CLEU-parity lane.

## Wave committed, parity lane running (2026-10-22, orchestrator)
- Clock lane reconciled (trail + signal + bench/clock_align_2026-10-22.md
  verified; scope held; missing-skill reporting confirmed — seat lacks the
  four skill IDs, manual equivalents ran). Full suite BEFORE commit:
  48/0, luacheck 2/0.
- Committed f142502 on main (60 files; excluded .vscode/settings.json +
  luac.out). Already on main — no merge needed.
- CLEU-parity lane ses_e9ad559f0ffe38c9yw4R6T0Hpa dispatched (desk
  swing-cleu-parity), four skills explicit, lib-touch ban + HU-31 scope in
  the prompt. Lane files its own bench artifacts (HU-32).

## Standing preference (2026-10-22, operator)
- IDE diagnostics stay ON (undefined-field/global, need-check-nil, etc.).
  The operator uses them to catch what lanes miss. Pasted diagnostics are
  review findings: verify each against the tree, fix if real, prove why if
  noise. Never propose disabling them again.

## Review finding triaged: hiding_anchor_frame type check (2026-10-22)
- Copilot: ensure get_hiding_anchor_frame can't return a non-frame.
- Verdict: NOT REAL, no change. Single writer (bars.lua:116, always a fresh
  CreateFrame, no early return between anchor creation and assignment);
  single reader path (bars.lua:243 + :500-506 nil-guard). Anchor exists
  ⟹ property is a frame — the scenario needs a writer that does not exist.
  A type check would be dead armor.

## G1+G2 class lane dispatched (2026-10-22, orchestrator)
- Lane ses_e9ac5b3f1ffeDW19XQj5tSNz34 (desk swing-class-gaps), four skills
  explicit. Scope: G1 interrupt/fail queue-tint clears (warrior/hunter/
  druid) + G2 neutral-handling registration expansion with bars_state/
  main_init pin re-cuts. main.lua/bars/run.sh/TOCs vendored off-limits.

## Wave committed (2026-10-22, orchestrator, operator order)
- Full suite BEFORE commit: 48/0, luacheck 2/0. New 3rd warning (warrior
  unused duration init) fixed directly (one-word, behavior-neutral, both
  branches assign), file re-linted 0/0, real_wire re-run 882/0, full suite
  re-run 48/0 + floor restored. Direct fix documented here per HU-26.
- Lane's per-gap file:line detail preserved in its handoff + desk journal;
  no bench file from that lane (owed, lanes' workspace).

## Hunter bars wave committed (2026-10-22, orchestrator)
- Continuation forced the committed legs (were /tmp-only): hunter_state
  +15, hunter_guide_state +6, mutations M1/M2 kill on exactly those legs.
- Full suite BEFORE commit: 48/0, luacheck 2/0. Scope: hunter.lua +
  two suites + bench/journals. U1-U3 in-client owed; C3 nextaction_ui
  melee-gate noted for the handoff, not a ruling question.

## GCD crash fixed + committed (2026-10-22, orchestrator)
- In-client throw (main.lua:1160 index nil, caught by H3 isolation): GCD_OVER
  looped all hands hiding gcd_bar; lazy-unbuilt hands have no visuals frame.
  Guard via bar_is_built (bars.lua owns it); gcd_bar unconditional with the
  frame, verified. Leg in main_init §4b-ii (no-throw + per-hand hide proof);
  mutation reproduces the exact in-client signature.
- Full suite BEFORE commit: 48/0, luacheck 2/0. Follow-up lane report
  reconciled (scope held, focused suites green, mutations kill).

## HUD known-gate wave committed (2026-10-22, orchestrator)
- Lane reconciled: scope held (hud.lua, paladin, shaman, hud_state +
  bench/desk trail); lane also removed the stray luac.out. Per-class
  verdicts accepted (paladin/shaman aligned; hunter/warrior/druid/rogue
  proven clean, no change). Mutations M1/M2''/M3/M4 kill; searing revert
  is behavior-identical (noted, accepted).
- Full suite BEFORE commit: 48/0, luacheck 2/0 floor.
- Owed in-client: U1 leveling hide/show + U2 blocked-call watch on the new
  per-tick book probes (isolation-bounded, but watch the log).

## Release audit dispatched (2026-10-22, operator: no buggy release)
- audit-practice ses_e9a40e9d4ffeEs461fILQ8v4p1: practice_*.lua + practice tests.
- audit-hud-options ses_e9a40e9d4ffd743vBH5iyaU0ay: hud/config/options + tests.
- audit-core ses_e9a40e9c3ffenICsds1XQvH3fU: main/bars/compat/swing_source/diag/utils + core tests.
- audit-hsp ses_e9a40e9c2ffef8L8jJODWWqmwB: hunter/shaman/paladin + guides.
- audit-rwd ses_e9a40e9c2ffdbIckpziky0p7V8: rogue/warrior/druid + guides.
- Scopes disjoint by file; all four skills explicit in every prompt; full
  run.sh + commit stay orchestrator-owned.

## Practice audit reconciled, held for wave commit (2026-10-22)
- Lane DONE, trail complete (journal + done signal). Scope verified:
  practice_ui.lua +9 (combat-pause deadline shift), practice_ui_state.lua
  +38 (§22b1b, 10 asserts). Other Ms in tree (main/bars/hunter.lua +
  hunter_state) belong to still-running lanes — not touched, commit waits
  for all five. No bench file from this lane (detail in handoff + journal).
- Accepting the fix; holding commit until hud-options/core/hsp/rwd land so
  the wave commits once with one full 48-step proof.

## HUD+options audit reconciled, held (2026-10-22)
- Lane DONE, trail complete. Scope verified: config_presets (shaman
  mirrors explicit-false x3), hud_templates_state (+37 pins), option_tables
  comment-only reword. F1 template-stale-slot + F2 stale comment fixed with
  red+green mutations. Rest verified-clean with file:line.
- Noted, not mine: bench/hud_templates_2026-10-19.md §5 stale vs 11 slots
  (bench = lanes' workspace); S-T2 mirrors on/off = operator design call.
- Still running: core, hsp, rwd. Commit waits for all five.

## HSP audit reconciled, held (2026-10-22)
- Lane DONE, trail complete (journal + signal + bench report). Scope
  verified: hunter.lua +104 (4 id-only sites → id-primary/name-secondary),
  hunter_state +17 legs. Mutations kill exactly the name legs.
- C3 confirmed-not-fixed (hunter guide dead at range — needs gated lane;
  handoff, not a ruling ask). Shaman/paladin proven clean.
- Still running: core, rwd. Commit waits for all five.

## Core audit reconciled, held (2026-10-22)
- Lane DONE, trail complete (journal + signal + bench/audit_core_2026-10-22.md).
  Scope verified: main.lua +55 (6 hardenings incl. GCD guard region),
  bars.lua +17, bars_lazy +75 (§6), main_init +13 (§4b-iii). F1 retracted
  with byte evidence (no phantom fix). Mutations M1-M4 kill.
- Still running: rwd only. Commit waits for all five.

## Dispatch (2026-10-25, operator wave: deep audit + hunter bars/range + practice timeline + clients + version)
- Operator scope (verbatim intent): deep audit of the actual code + improve/optimize/enhance ideas;
  background alpha not see-through (ANSWERED: backdrop only); fix hunter mainhand vs ranged bar;
  ranged distance as its own bar that fills toward melee range (melee weaving);
  practice mode should be a MOVING timeline showing when to click each ability;
  works on classic_era / classic_anniversary ("classic") / classic_titan (Titanforge) / Forever / Retail;
  native wow-ui-source API instead of our Lib where the client actually has it.
- Operator rulings taken this session (question tool, verbatim answers):
  1. Version: treat "0.0.1" as the INCREMENT -> 2.1.2 becomes **2.1.3** (all 7 TOCs + main.lua + CHANGELOG).
  2. Swing engine: **native API on Forever/Retail, keep the vendored lib on the classic line**.
     Verified today: PLAYER_SWING exists ONLY on origin/forever; classic_era / classic_anniversary /
     classic_titan / live have no swing event and no Blizzard_SwingTimer. No native swing API to copy on classic.
  3. Background alpha: **backdrop only** (not the colored fill).
  4. Practice timeline: **fixed moving playhead with upcoming abilities** (not the old auto-scroll log).
  5. Ranged distance: **standalone fill bar, ON by default for hunters, opt-in elsewhere**.
- No read-only agent seats this wave (operator order): all six lanes are shell-capable `general` desks;
  cross-client claims must cite branch+path+line via `git -C /home/sam/wow-ui-source`.
- Baseline BEFORE the wave: `bash tests/run.sh` = 48 steps, **3 failed** (lrc_guard_state 83/141,
  range_source_state 12/148 twice) — the vendored LibRangeCheck re-acquired `CheckInteractDistance`
  (lib :413/:463) after the HU-23 removal; a later vendored update regressed it. Assigned to
  cross-client-engine (Task A). Everything else green; luacheck 2/0 in 90 files.

| Lane | Scope | State | Session |
|---|---|---|---|
| bars-range-hunter | bars.lua, weave_range.lua, classes/hunter.lua, hunter_ui.lua + hunter/weave suites; hunter mh-vs-ranged truth table + standalone melee-weave distance bar | running | ses_e8c1621f9ffe2EsMz0luIPLGi1 |
| practice-timeline | practice_ui.lua, practice.lua + practice suites; diagnose practice start path + moving-playhead timeline with class-provider seam | running | ses_e8c1621f8ffed6PG4TtSX6z4KQ |
| appearance-options | config_presets.lua, option_tables.lua, config.lua + options suite; opaque backdrop default + one-time migration, weave bar default/option copy | running | ses_e8c1621e7ffeyBJR3xQ7rn9evk |
| cross-client-engine | swing_source.lua, compat.lua, main.lua (named regions), vendored LibRangeCheck protected-call removal + engine/range suites; Forever native events, Retail inert, classic lib path | running | ses_e8c1621e7ffdcFA2q0LElF5CJ0 |
| audit-core | READ-ONLY scope: main/bars/compat/swing_source/guard/utils/diag/ldb/enemy_swing/hud/config — per-frame cost, event paths, growth, reliability, idle cost + ranked fixes/ideas | running | ses_e8c1621e6ffeR60CNSDru9YA6z |
| audit-features | READ-ONLY scope: classes/*, practice*, guides, UI, options — behavior vs documented intent, class isolation, practice integrity, per-client drift, perf/reliability + ranked fixes/ideas | running | ses_e8c1621e6ffdZv0hT90HVWbeAZ |
| version-docs | 2.1.3 bump (7 TOCs + main.lua + CHANGELOG) + README/TESTING truth pass | queued (after builders; owns main.lua/CHANGELOG) | — |

## Orchestrator findings filed into the wave (2026-10-25, pre-reconcile, verified in-tree)
- **Baseline is not green**: the vendored `LibRangeCheck-2.0` re-acquired the HU-23 protected call
  (`Libs/LibRangeCheck-2.0/LibRangeCheck-2.0/LibRangeCheck-2.0.lua:413` declares `CheckInteractDistance`,
  `:463` calls it) after a later vendored update. `tests/lrc_guard_state.lua` (83/141) and
  `tests/range_source_state.lua` (12/148) catch it. This is a shipping defect: on TBC Anniversary the
  client blocks the protected call (`ADDON_ACTION_BLOCKED`), so range display dies. Cross-client lane owns it.
- **Hunter mh-vs-ranged lead (verified in the lib, fix not yet ruled)**: the lib's
  `UNIT_SPELLCAST_SUCCEEDED` blanket cast-reset (`LibClassicSwingTimerAPI.lua:596-605`) restarts
  mainhand AND offhand on every non-Retail cast when `unit.casting` is set. Auto Shot 75 is exempt via
  `noreset_swing_spells` (:1030/:1143/etc), but hunter shot casts (Steady 34120 / Multi 2643 / Aimed 19434)
  are not — so each shot can re-anchor the melee bars and the mh bar looks welded to the ranged cycle.
  Routed to both the bars and cross-client lanes with an instruction to confirm against the real version
  branch and choose an our-side suppression vs a per-version lib `noreset` entry (HU-29 fork-patch rule).
- **Practice timeline is a post-fight event log, not a moving trainer**: `practice_ui.lua:3198-3300`
  places icons at `event.time * TIMELINE_PPS` and jumps the scrollbar to max on each render; the archived
  TBC build does the same (`docs/swedge/SwedgeTimer_TBC/practice.lua:2246-2370`). Lanes are paladin-hardcoded
  in shared `practice.lua:128-142` (SoB/CS/Consec/SoC/Judge), so non-paladin drills have no meaningful
  timeline. The moving-playhead rebuild is new work, not a port.
- **Weave-range bar exists but is off and vertical**: `weave_range.lua` (269 lines) fills bottom-up beside
  PlayerFrame, default `weave_range_enabled = false` (`config_presets.lua:100`), and it already uses exact
  yards via `st.api.UnitDistance`. The operator's requested bar is a default-ON hunter bar, so the lane is
  re-shaping it rather than inventing a second distance widget. The old 4-state `hunter_ui` strip stays
  unless a lane proves it duplicates the new bar.
- **Version surface** (for the 2.1.3 lane): 7 TOC `## Version` lines + `main.lua:5 local version` +
  `CHANGELOG.md` top section. `README.md` carries no version. `ST.addon_version` is derived, no other
  file hardcodes it.

## Reconcile (2026-10-25): appearance-options DONE
- Verified, not trusted: `tests/appearance_defaults_state.lua` 145/0 in-tree; `tests/options_load_state.lua`
  3596/0; migration shape checked against `Libs/AceDB-3.0/AceDB-3.0.lua:88-131` (copyDefaults rawsets a new
  table) and the Classic-Retro collision (`config_presets.lua:255+` ships {0,0,0,0.85}) is guarded by
  `theme_preset`. I re-ran two mutations independently on a /tmp copy: hunter default -> false kills 4 pins;
  backdrop alpha -> 0.85 kills 8 pins. Kill confirmed.
- Scope held: config_presets.lua, config.lua, option_tables.lua, tests/appearance_defaults_state.lua (new),
  tests/options_load_state.lua. Fill alpha/border/HUD untouched.
- Accepted residual (lane-owned, documented): a deliberately picked pure black 0.85 is byte-identical to the
  old default and migrates opaque; no touched-tracking exists to distinguish it.
- Owed by orchestrator: `tests/run.sh` registration for `appearance_defaults_state.lua` (+ the other two new
  suites when their lanes land). `tests/toc_check.lua` currently fails exactly those registration pins —
  expected mid-wave, not a defect.
- Owed by bars-range-hunter: runtime gate in weave_range.lua must use `ST.weave_range_default_enabled`
  (nil == ON for HUNTER); steered.

## Reconcile (2026-10-25): audit-core DONE (read-only, no product edits)
- Trail verified: `bench/audit_core_perf_2026-10-25.md` (839 lines, new file), desk journal current,
  done signal `desks/audit-core/.signals/20261025T165010Z.json`. No product file touched (git diff confirms).
- Independently re-checked the two HIGHs against the tree: (R1) `main.lua:2501-2532` — `rf_update` returns
  before `set_bar_visibilities()` on `rf_disabled`, and the visibility pass sits OUTSIDE the pcall while the
  re-arm is the last line, so a throw kills show/hide for the session. (R2) `main.lua:1400-1415/1467-1480`
  suppression state has no combat-exit reset; `classes/paladin.lua:2214-2218` resets its own analogue,
  proving the omission. Both CONFIRMED; both pre-existing in HEAD.
- Other accepted findings for the next wave: HUD always-on layout poll + live trinket cooldown reads
  (`hud.lua:697-715,324-330`), TBC paladin 20 Hz × 40-row aura walk (`main.lua:1028-1051` →
  `classes/paladin.lua:590-600`), enemy_swing CLEU + LibStub per event while off (`enemy_swing.lua:586-592`),
  O1-O10 optimizations, 10 enhancements (5 confusion-reducers). Report also flags R3 class-picker
  `active_class` vs `player_class` mismatch, R4 init latch ordering, R5 bar-full timer handle hygiene.
- Not dispatched as fixes in this wave: main.lua is owned by cross-client-engine until it lands; the next
  wave owns R1/R2/O5/O6 (+O7/O8) as a core-engine lane and O1-O4/O9/O10 as a display lane. Pins to re-cut
  are filed in the report, not edited.

## Reconcile (2026-10-25): audit-features DONE (read-only, no product edits)
- Trail verified: `bench/audit_features_2026-10-25.md` (454 lines, new), desk journal current,
  done signal `desks/audit-features/.signals/2026-10-25T17-05-00Z.json`. No product file touched.
- Independently spot-checked the HIGHs:
  * `class_activation` half-wired CONFIRMED by inspection: `main.lua:791` activates the selected module,
    but `post_init`/event hooks still key `self[self.player_class]` (e.g. :970, :1098) and
    `hud.lua:524`/`nextaction_ui.lua:135` also use the playing class. Auto default masks it; an explicit
    pick loads a dead module. Next wave: one key for dispatch/settings (or label the picker dev-only).
  * Era/SoD range probe dead CONFIRMED: `classes/hunter.lua:180 steady_id_by_family.ERA = 56641` and
    `/home/sam/wow.export/Spell.csv` (1.15.9 client, 2.0 MB) has ZERO rows for 56641; the guide's
    `range_token` falls back to that id (:3331-3334), so `target_in_range` is always nil on Era/SoD and the
    out-of-range HOLD can never fire. Next wave: family-correct range token (Auto Shot 75 on Era).
- Other accepted for next wave: practice prompt/button re-grade without a timing gate (stats/mastery/
  perfect_ten farmable; XP capped), hunter gather 3-6 aura walks per 50 ms tick, practice pcalls hiding a
  broken class grader. All pre-existing; all cited in the report.
- Note recorded from the lane: `practice_ui_state` was transiently red mid-wave and passes 2608/0 at its
  final snapshot — orchestrator's full run is the authority, not the lane's window.

## Reconcile (2026-10-25): practice-timeline DONE
- Verified, not trusted: `practice_timeline_state.lua` 102/0, `practice_state.lua` 1582/0,
  `practice_ui_state.lua` 2608/0, in-tree. Independent mutation on a full /tmp copy (event_x sign
  flipped) kills 5 pins — kill confirmed. Scope held: practice_ui.lua, practice.lua + the three suites.
  LF preserved (practice_ui/practice have 0 CR lines; the CRLF files were untouched).
- Accepted: class drills had NO timeline at all (`begin_drill_session` never touched the frame; the toggle
  was inside the sim-only block at practice_ui.lua:2115) — REAL and fixed by showing the strip in every
  session. The old view was a past-only auto-scrolled log; the archive has the same log, not a playhead.
  Paladin-hardcoded lanes in shared practice.lua are now resolved from the ACTIVE class
  (`ui.timeline_lanes`/`ui.timeline_lane_index`, cached per class).
- Shipped contract: fixed 25% playhead, 6 s horizon, 75 px/s, 12-icon reused pool, one OnUpdate on the
  strip frame (hidden => no tick), schedule rebuilt at PLAYHEAD_SCHEDULE_INTERVAL, provider seam
  `practice_panel.timeline_lanes` + `upcoming(ui, now, horizon)`, neutral fallback from the active class's
  own live+engine rotation rows labelled "Rotation cadence (preview)". History is now the opt-in button.
- Owed by orchestrator: run.sh line `tests/practice_timeline_state.lua`.
- Owed by a follow-up lane (classes/hunter.lua is owned by bars-range-hunter until it lands): hunter
  `practice_panel.upcoming` so the strip shows the real shot schedule instead of the neutral preview.
  Other filed items (bench §A5): drill sessions ship with no keybinds (click-only until right-click assign),
  reset_keybinds wording, swallowed start error, toggle_fight per-class block, fixed row layout.

## Reconcile (2026-10-25): cross-client-engine DONE (pending one operator ruling)
- Baseline RED closed: `lrc_guard_state` 141/0 and `range_source_state` 148/0 in-tree; the 2026-10-25
  re-vendor (commit `6e2bc2d`) had replaced the HU-23 LRC file with pre-patch upstream. The lane ported the
  guard package 1:1 onto the new upstream base (API probes, item/spell absence+secret guards, empty-list
  getRange guard, conditional event registration) and dropped the interact ladder entirely.
- Engine matrix independently re-verified today: `PLAYER_SWING` exists only on `origin/forever`
  (`SwingTimerDocumentation.lua:43-52`, enum :71-82); `classic_era`/`classic_anniversary`/`classic_titan`/
  `live` have no swing event and no Blizzard_SwingTimer. The lane's choices match: lib on classic,
  swing_source on Forever, inert on Retail, no classic-lib fallback (HU-31).
- swing_source changes accepted: weapon swap now RESTARTS at the equipped duration (mirrors Blizzard :319-330),
  world entry STOPs live cycles before clearing (no silent drop), event omissions re-justified with lines
  (PLAYER_TARGET_CHANGED / PLAYER_SWING_RANGE_UPDATE are display-only and the latter needs
  C_SwingTimer.EnableRangeCheck). main.lua diff is the diag `swing_engine=` line only.
- Hunter cast-reset addendum: the lane CONFIRMED the lead with corrections — Auto Shot 75 was not in
  `noreset_swing_spells`; Steady is already exempt on BCC/Wrath; the unexempt damage shots were
  Multi/Aimed/Arcane/Serpent. It patched the VENDORED SWING LIB's per-version `noreset_swing_spells`
  (+47 lines, Era/BCC/Wrath) and added a real-lib hunter leg (978/0, 2 expected-fail HU-29; 9/9 muts).
  This is HU-29 option (b) exercised without an explicit operator ruling → raised to the operator.
- Filed, not fixed: Wrath/Titanforge `reset_swing_spells[75]` still restarts mainhand+offhand on Auto Shot
  (`LibClassicSwingTimerAPI.lua:1196`), defeating the class guard there; one-line removal recommended.
- Suites: `swing_source_state` 159/0, `engine_matrix_state` 101/0, `real_wire_state` 978/0 (2 xfail).
  run.sh line owed for `engine_matrix_state.lua`.

## Reconcile (2026-10-25): bars-range-hunter DONE + two operator rulings
- Verified in-tree: `weave_range_state` 90/0, `weave_bar_state` 105/0 (new), `hunter_state` 1824/0,
  `bars_state` 956/0. Desk journal carries three passes + 3 signals (done + hands-up + checkpoint).
- Task A root causes (both fixed, both real):
  1. ENGINE: the vendored lib restarts BOTH melee hands on every completed tracked cast
     (`LibClassicSwingTimerAPI.lua:596-605`); Auto Shot is a cast on the classic line. The lane proved it on
     the SHIPPED library (Era/Anniversary/Titanforge profiles), and corrected the inherited lead: no
     `noreset_swing_spells` table contains 75; every `[75]` is in `ranged_swing` (starts the ranged cycle).
     Fix as shipped: class guard `ST.HUNTER.suppress_auto_shot_melee_reset` arms the engine's own
     `preventSwingReset` during an Auto Shot cast (range-dependent).
  2. LAYOUT: `hunter_ui.sync_melee_anchor` moved mainhand/offhand under the ranged bar whenever the hunter
     cast bar was visible — and the cast bar is visible for the Auto Shot hidden-window face for 0.5 s of
     EVERY ranged cycle. The re-anchor is retired; the bars no longer hop into the ranged stack with no
     melee activity.
- Task B: standalone horizontal distance bar, own top-level frame, exact yards only (`api.UnitDistance`),
  fill 1.0 at ≤5 yd / 0 at ≥35 hunter (30 others), label + MELEE/IN RANGE/OUT, unknown hides (never paints 0),
  no unit reads on the disabled path, anchored above the ranged bar with a height-based cast/RF reserve and
  screen clamp. Nil gate delegates to `ST.weave_range_default_enabled` (appearance lane's helper), no class
  token hardcoded. Driver pcall-isolated + quarantine, 0.05 s enabled / 0.5 s disabled.
- OPERATOR RULINGS TAKEN THIS SESSION:
  * Vendored swing-lib patch: **REVERT — our-side only.** Cross-client lane re-dispatched to restore the lib
    byte-exactly and move the hunter-shot exemption into `classes/hunter.lua` (+ main.lua only if provable).
  * Auto Shot at melee: **NEVER RESET MELEE** (reference in-melee exception rejected). The class guard must
    arm all hunter shots, in melee included. Wrath/Titanforge `reset_swing_spells[75]` is the residual: if it
    cannot be suppressed deterministically our-side, it is documented, not heuristically swallowed.
- Resolved the lane's hands-up by the second ruling above (no in-melee exception).
- Owed: run.sh lines for `weave_bar_state.lua`, `appearance_defaults_state.lua`, `practice_timeline_state.lua`,
  `engine_matrix_state.lua`; option desc fix (dispatched to appearance-options); `main.lua:985-990` stale
  comment (cross-client lane); in-client checks in bench §11.

## Follow-up reconcile (2026-10-25): appearance-options desc correction
- `option_tables.lua:195-224` now describes the landed standalone bar accurately (exact yards, no band
  fallback, MELEE/IN RANGE/OUT, unknown hides, 35 yd hunter / 30 yd others, hunter-ON). Getter/setter/
  disabled unchanged. `options_load_state.lua` 3606/0 (+10 pins), appearance 145/0, luacheck 0/0.
  Pins read 5/30/35 from the module so copy and code cannot drift; two mutations kill. run.sh registration
  already added by orchestrator (toc_check 1082/0).

## OPERATOR CORRECTION (2026-10-25): spell-id vs spell-name per client
- Verbatim: "titanforge aka wotlk doesnt use spell ids either. stop guessing. each has their own client."
  Combined with the earlier line ("tbc is classic_anniversary and doesnt take spell ids it needs spell
  names"):
  * **ERA (classic_era 1.15.9, including SoD runes)** — state queries take IDS. SoD is the SAME client as
    Era; SoD runes are extra ids on Era, NOT a separate family. Never substitute a TBC/Wrath id for an Era
    one.
  * **TBC (classic_anniversary 2.5.6)** — state queries take localized NAMES, never bare ids.
  * **WRATH / Titanforge (classic_titan 3.80.2)** — state queries take localized NAMES, never bare ids
    (operator in-client fact; API docs say number, so the operator's client behaviour is the authority).
  * Each family is gated separately — no combined "classic-line" name/id branch.
- Consequences to fix, in order:
  1. `compat.api.get_spell_query` (compat.lua:1661) returns a name only on TBC. It must return a name on
     TBC **and** WRATH, with explicit per-family branches (ERA ids; TBC names; WRATH names; FOREVER/Cata/
     Mists untouched until proven).
  2. Every class's token helper that hardcodes TBC must use the compat helper (or add WRATH): hunter
     `spell_token` (classes/hunter.lua:25), shaman inline branches, druid inline branches, plus the
     paladin/warrior/rogue helpers that already call `get_spell_query` (they inherit the fix).
  3. The new hunter shot guard must not rely on our id tables alone for Titanforge: add a canonical-NAME
     fallback (class `spell_name` fields), because Titanforge's ids may not match our tables.
  4. `classes/hunter.lua:180 steady_id_by_family.ERA = 56641` is a WRATH id with zero rows in the 1.15.9
     `Spell.csv`; the Era range token must be a real Era ability (Auto Shot 75 / Multi 2643), never an
     invented Era Steady Shot.
- Evidence limit: only the 1.15.9 Era export exists locally (`/home/sam/wow.export`); no Titanforge client
  data offline. Titanforge claims are the operator's in-client fact + name-based queries, and must be marked
  as such in tests/reports.
- Queued lane after cross-client-engine lands (it owns compat.lua now): `spell-resolution-matrix` —
  compat helper + all six class token helpers + per-family truth pins (Era ids incl. SoD ids; TBC names;
  Wrath names) + mutations for a wrong-family substitution.

| Lane | Scope | State | Session |
|---|---|---|---|
| spell-resolution-map | READ-ONLY scope: compat + all six class token helpers + every state-query call site; per-family id/name truth map (Era ids incl. SoD, TBC names, Wrath/Titanforge names), change plan, Titanforge risk list | running | ses_e8aa9d64bffeGUinJ165TqYVw0 |

## CORRECTION (2026-10-25, operator): do not remove or replace spell ids
- Verbatim: "if u remove shit u will have to research the spell ids again." My earlier instruction to
  replace `steady_id_by_family.ERA = 56641` (and any id flagged absent from `/home/sam/wow.export`) is
  WITHDRAWN. The 1.15.9 export does NOT prove an id invalid: SoD rune/seasonal ids may be absent from it,
  and SoD shares the Era client. **No id is removed, replaced, or "corrected" without a fresh id research
  and an explicit operator ruling.** Steered both running lanes (cross-client-engine, spell-resolution-map)
  accordingly; the map lane now lists unverified ids under "do not touch without re-research", not as fixes.
- Additive work only: keep every existing id table; add the family-correct NAME query for state calls
  (TBC + Titanforge) and a name fallback for the hunter guard that deletes nothing.

## Full suite GREEN (2026-10-25, after all cancellations + stale-pin re-cut)
- `bash tests/run.sh`: **52 steps, 0 failed**; luacheck **2 warnings / 0 errors in 94 files** (floor).
- Stale pin fixed by the practice desk: `tests/rogue_state.lua` now asserts the shared `drill_now` clock
  (`practice_begin_fight` + `playhead_refresh` + `playhead_draw` from one `api.get_time()`); rogue_state
  1137/0; 3 mutations kill. No production code changed for it.
- Vendored swing lib confirmed byte-identical to HEAD (revert held). No existing spell id removed.
- Honest residual: the cancelled cross-client desk's journal/bench still describe the withdrawn lib patch
  as the chosen fix (its workspace is frozen; NOT edited by the orchestrator per HU-32). The tree is the
  authority: lib clean, our-side guard `ST.HUNTER.suppress_shot_melee_reset` shipped, real_wire 1005/0 with
  3 expected-fails (2 HU-29 + the Wrath Auto Shot residual).

| Lane | Scope | State | Session |
|---|---|---|---|
| spell-resolution | compat.get_spell_query + six class token helpers; NAMES on TBC **and** WRATH, ids on ERA (SoD same client), explicit per-family gates, additive only — NO id table edits/removals; new per-family suite | running | ses_e8aa2db20ffeFhCha64diU8p0y |
| version-docs | 2.1.3 bump (7 TOCs + main.lua:5 + CHANGELOG) + README/TESTING/AGENTS per-client spell-query truth pass | queued (after spell-resolution; owns main.lua/CHANGELOG) | — |

## Final wave state before operator in-game test (2026-10-26)
- Full suite: **53 steps, 0 failed**; luacheck **2 warnings / 0 errors in 95 files** (floor). `toc_check`
  1082/0 after registering the three new suites (`weave_bar_state`, `practice_timeline_state`,
  `appearance_defaults_state`, `engine_matrix_state`, `spell_query_family_state`).
- Landed + verified in-tree:
  * Hunter mainhand/ranged: lib cast-reset proven on the shipped lib, fixed OUR-SIDE
    (`ST.HUNTER.suppress_shot_melee_reset` arms the engine's own `preventSwingReset` for every hunter
    ranged shot, melee included); the hunter cast-bar melee re-anchor is retired. **Vendored
    LibClassicSwingTimerAPI is byte-identical to HEAD** (operator ruling: our-side only).
  * Standalone ranged-distance bar: own horizontal frame, exact yards only (`api.UnitDistance`), fills to
    5 yd / empty at 35 hunter (30 others), MELEE/IN RANGE/OUT label, unknown hides, hunter default ON,
    other classes opt-in via `ST.weave_range_default_enabled`.
  * Practice: moving 25% playhead strip, 6 s horizon, cues right-to-left, 12-icon reused pool, one OnUpdate
    on a hidden-when-idle frame; class drills previously had NO timeline. Provider seam
    `practice_panel.upcoming` + `timeline_lanes`; neutral cadence fallback from the active class's own
    rotation rows. History is the opt-in log.
  * Appearance: backdrop alpha 1.0 default + one-time migration (only the exact untouched old default),
    Classic-Retro/custom colors preserved. Fill/border/HUD untouched.
  * Cross-client engine: HU-23 LRC protected-call removal restored after the 2026-10-25 re-vendor (0
    `CheckInteractDistance(` sites; lrc_guard 141/0, range_source 148/0); Forever weapon-swap restarts and
    world-entry STOPs (mirrors origin/forever `Blizzard_SwingTimer`); Retail inert. `swing_engine=` diag.
  * Spell queries: **Era ids (SoD same client); TBC + Titanforge localized names first, ID FALLBACK
    preserved** (operator: "i never banned fallback to ids"). No id table entry removed; the two additive
    rank-1 entries (3044/1978) stay.
  * Version: 2.1.3 across 7 TOCs + `main.lua:5` (docs desk finalizing; verify after).
- DEFERRED on operator order ("dont do it if its a big thing just get current codebase in sync"): the
  leveling guard (known-spell-aware HUD + next-action filtering). HUD already has the `spell_known` hide
  gate; a full rotation filter is a separate wave.
- Residuals to disclose, not fix now:
  1. Titanforge: the shot guard matches our id tables for Multi/Aimed/Arcane/Serpent; if Titanforge's
     client ids differ, the guard can miss even though state queries now try names. Name fallback for the
     guard is a follow-up.
  2. Titanforge: stock lib `reset_swing_spells[75]` still restarts melee on Auto Shot; no deterministic
     our-side filter (operator forbade lib edits). Documented as xfail in real_wire.
  3. No in-client proof for any of this wave. The bench reports say so; in-client checks are in
     bench/*_2026-10-25 §in-client and TESTING.md.
  4. The cancelled cross-client desk's bench/journal still describe the withdrawn lib patch as chosen
     (frozen workspace; HU-32). The tree is the authority.
  5. Leveling guard deferred.
- Docs sync: CHANGELOG/README/TESTING/version by `version-docs` desk; AGENTS.md deliberately untouched
  (operator: no bloat; the cross-client principle already lives there). workshop.md lessons 19-22 added
  (no correction streams; id absence is not proof; per-client name/id + fallback; cancelled lanes frozen).

## Version + docs finalized (2026-10-26)
- **2.1.3** in all 7 TOCs + `main.lua:5`; `ST.addon_version` derives. CHANGELOG `## [2.1.3]`
  (Added/Changed/Fixed/Hardening, no leveling claim, no in-client claim). README: hunter range bar,
  practice cue strip, opaque backdrop — three surgical lines. TESTING: five in-client bullets.
  AGENTS.md deliberately UNTOUCHED (operator: no bloat; the cross-client principle already lives there).
- Orchestrator corrected the docs desk's one wrong TESTING claim: `/st diag` DOES print
  `swing_<hand>=<start>/<update>/<stop>` + `swing_last` (main.lua:2757-2780); the bullet now tells the
  operator to read those, not to dump the addon table.
- Final `bash tests/run.sh`: **53 steps, 0 failed**; luacheck **2 warnings / 0 errors in 95 files**.
  `luac.out` restored to HEAD after the run (build artifact, not part of the wave).
- Line endings verified: CHANGELOG 1136/1136 CRLF; README/TESTING/TOCs/main.lua LF as before; no mixed
  endings in any modified file.
- Honest residuals for the test session: (1) no in-client proof for anything in the wave; (2) Titanforge
  shot-guard name matching is id-table based (state queries are name-first with id fallback); (3) stock
  lib `reset_swing_spells[75]` still restarts melee on Auto Shot on Wrath/Titanforge (xfail, operator
  forbade lib edits); (4) `steady_id_by_family.ERA = 56641` left untouched — id changes need fresh
  research + operator approval; (5) leveling guard deferred by operator order.

## README credit added (2026-10-26, operator order)
- `README.md` Links section now credits **forktale** for the paladin seal-twist work, with the
  operator-provided CurseForge link: https://www.curseforge.com/wow/addons/swedgetimer-tbc-anniversary-update
- Docs-only change; no code/tests/version impact. README LF preserved.

## Practice timeline restyled to the operator's reference (2026-10-26)
- Operator supplied the forktale/TBC timeline screenshot: "Practice should look like this."
  The cue strip now wears that layout (practice_ui.lua `build_playhead`):
  * left lane rail, 64 px: one 16 px icon + name per lane (the paladin's sim lanes
    SoB / Melee / CS / Consec / SoC / Judge, resolved through `ui.timeline_lanes()` so the
    strip and the History log never disagree);
  * 34 px ruler band: title on the right, one tick + `m:ss` label per second, the labels
    riding the SAME `timeline_event_x` maths as the cues (clock scrolls, playhead fixed);
  * banded 24 px lane rows (alternating shade), the 22 px cue icons in their own lanes;
  * fixed playhead line at 25%, full lane height + 6 px into the ruler; close X hides the
    strip for the rest of the session (a later `playhead_show` restores it);
  * default position moved to the top of the screen (`TIMELINE_DEFAULT_Y` -200 -> 260,
    shared with the History log, matching the screenshot).
- Cue lanes: `st.practice.timeline_cadence` now derives a cue's lane from the sim's own
  `cast_timeline_lane` when the rotation row does not name one, so preview cues land on
  the same rails as recorded events. No ids touched.
- Tests re-cut: `tests/practice_timeline_state.lua` lane geometry (34 + 24n + 14), plus a
  new layout block (rail names/icons, 24 px rows, ruler 0:00 -> 0:01 under the playhead,
  CS cue on row 3, close X hides/restores). `tests/practice_ui_state.lua`: frame count
  83 -> 85 (close button + lane rail), default y -200 -> 260, one-lane strip height.
  Four mutations on /tmp/opencode copies kill the new pins (lane height, ruler loop,
  derived lane, close no-op).
- `bash tests/run.sh`: **53 steps, 0 failed**; luacheck 2 warnings / 0 errors in 95 files.
- Docs: CHANGELOG [2.1.3] timeline bullet, README Practice paragraph, TESTING practice
  timeline bullet. Version unchanged (2.1.3, not yet tested in client).
- Cue art follow-up (same restyle): the cue icon pool gained the practice display's split
  halves, and `playhead_dress` falls back to `set_step_texture(event.key)` when a cue has no
  `spell_id` of its own (the paladin rotation rows carry per-family id MAPS, not a single id).
  That gives the strip the panel's CS art and the twist's split Command/Blood icon; an
  unmapped key still hides (unknown-hides). Pins: step art for a no-id CS cue + all four
  twist-half assertions; a /tmp mutation that disables the fallback turns 6 checks red.

## Practice trainer: reference layout, start/stop clock, both frames (2026-10-26)
- Operator reference: https://media.forgecdn.net/attachments/1587/946/twist-practice-ui-png.png
  (local copy bench/assets/twist_practice_ui.png). Requirement: BOTH frames in practice; the top
  timeline is the timed surface; Start Fight starts it, Stop freezes it; XP from timed graded presses;
  options must offer "Open Practice Panel"; only the panel's X stops practice; Era + TBC; every class.
- Landed:
  * `build_playhead` now wears the reference chrome: lane rail, 46 px ruler, 24 px banded rows, m:ss
    labels riding the same event_x maths, rotation band (label + up to 5 sequence icons) top-centre,
    close X, default y 260. Cue art falls back to `set_step_texture(event.key)` (CS + twist split).
  * Movement clock: `ui.playhead_running` / `ui.playhead_frozen_at`. `ui.start` opens the PALLY SIM
    session stopped (archive "wait for Start Fight"); `start_fight` runs it (before the drill branch,
    so every class's fight sets it); `stop_fight` freezes at the stop second; `begin_drill_session`
    runs only if the class's own session already started its fight; `ui.stop` clears both.
  * Both frames for every class: `playhead_available` also accepts the class's own panel `order`;
    `playhead_cadence_rotation` builds rows from `practice_class_def` (label + spell_id) when the
    class publishes no `practice_rotation` - never the paladin sim's order for another class.
  * Options: all 7 practice entries now label "Open Practice Panel" and prefer `ui.open` (open-only,
    never stops), with a `toggle` fallback for a half-loaded shell. Closing AceConfig never stops.
  * XP: verified the existing per-attempt path (`record_graded_attempt` -> `record_progress_attempt`)
    awards per graded press and repaints the badge; opening/idling earns nothing. No new XP formula.
- Tests: practice_ui_state re-cut for the stopped session (start/stop lifecycle, fight button, pools
  start their own fight, 90 frames incl. 5 band icons), practice_timeline_state 128 checks
  (reference layout, ruler 0:00->0:01, band, class-order fallback). Full `bash tests/run.sh`: 53/0.
- Independent audit desk dispatched with the image link: ses_e89faba11ffe2wefox8rtCnG7G (report will
  land in bench/practice_audit_2026-10-26.md; reconcile before finalizing docs).

## Practice UI check vs the reference: full-width timeline + panel chrome (2026-10-26)
- Operator (this session): "check the practice ui ... it should of been remade so its similar to image
  i posted. focus on the top part and the menu on right side." Reference: the same CurseForge
  screenshot (bench/assets/twist_practice_ui.png). Read the audit first
  (bench/practice_audit_2026-10-26.md): the two-frame wiring, Start/Stop ownership and timed XP were
  already sound; the operator-visible gaps were all CHROME/SCALE (audit D2/D3/D4/D5/D6/D7).
- Verified as-built (code + sandbox dump of the built frames): panel 210x428 with the grid, the port's
  readouts and a 90 px button pair; strip 722x250 at the 600 px fallback track (24 px rows, 46 px ruler,
  22 px cues, 6 s horizon, 6 px ruler ticks); log 676x220. Both frames share `ui.timeline_x/y`.
- Landed (top part):
  * Screen-scaled track: `ui.timeline_track_width(rail, minimum, width)` - screen minus 2x10 px margins,
    the frame's rail and 12 px chrome, clamped to the 600 px fallback and 2000 px. Both frames use it
    (strip rail 110, log rail 60); `ui.playhead_track_width` / `ui.timeline_width` store the built
    geometry so `playhead_draw` never re-derives it. A sandbox/client with no UIParent width keeps 600.
  * Reference scale: ruler 46 -> 56, lane rows 24 -> 30, cue icons 22 -> 24, rail 64 -> 110, horizon
    6 -> 10 s (`TL_HORIZON_SECONDS`), pools 12/16 -> 20/26, default y 260 -> 300.
  * Ruler ticks are now FULL-HEIGHT second gridlines down the lanes (were 6 px marks above the track).
- Landed (right panel, reference order): bind hint "Right-click icon to map to action bar" under the
  grid, a clickable **(Reset)** link (sim panels only - `ui.reset_keybinds`; a drill panel's binds are
  its own module's) and 3 hairline separators; Bloodlust / Haste Pot are two equal 95 px halves; the
  reference order is haste pair -> Practice Rotation -> **Start Fight** -> **Timeline**; the port's
  readouts (fight timer, score, resource, DST, live hint) moved BELOW that block. "History" renamed to
  **Timeline** (the log the button opens), comments/docs updated.
- Tests: practice_ui_state 2697 -> 2716 checks (reference chrome, equal haste halves, y-order,
  (Reset) restores binds, drill panel has no reset/separators); practice_timeline_state 143 -> 157
  (track-width maths incl. clamps, full-width strip + log builds at 1920, gridline height/anchor).
  Stub additions: FontString/texture `SetPoint` recording. Six mutations (reset wiring, haste widths,
  hint text, track width, tick height, panel order) all killed on in-place backups, file restored.
  `bash tests/run.sh`: 53 steps, 0 failed; luacheck 0 errors.
- Left as documented limits (unchanged from the audit): the strip is a cadence PREVIEW, not the graded
  press schedule (D1); 8 paladin APL rows still have no art (D2); no scrollbar on the strip (D4 - the
  strip is a fixed window, the log has one); drill panels have no Timeline button (D6).
- Next: in-client pass on a 1920 client (TESTING "Practice timeline" + "Practice panel chrome"), then
  decide whether the strip should be flush at the top (DEFAULT_Y is the one-line dial) and whether the
  blank APL cues need the family-id art resolver.

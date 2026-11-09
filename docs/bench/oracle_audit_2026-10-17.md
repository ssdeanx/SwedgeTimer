# oracle_audit_2026-10-17 — full-round adversarial audit (standing rule)

Date: 2026-10-17. Desk: oracle. READ-ONLY on code (harness + luacheck re-run only; nothing modified).
Scope: everything since the last oracle pass — build-out round 1 (10 lanes) + competitor-scan + shaman-weave + options (27) + enterprise-grade (5) + reconcile + 120105-matrix + options-followup + hud-reflow.
Method: read desks/journal.md, CAIRN.md, AGENTS.md, hands-up.md (HU-1..HU-4), bench/lessons.md, bench/verify_bank.md, bench/discover_features.md, bench/competitor_scan_2026-10-17.md, all 17 bench/buildout_* reports; spot-checked tree claims with grep + one harness re-run.
Evidence baseline re-confirmed in-tree: `bash tests/run.sh` → **35 steps, 0 failed**; `luacheck .` → **2 warnings / 0 errors** (both KEEP-ruled standing: compat.lua:34, main.lua:72).

## Verdict: READY-WITH-FIXES (0 BLOCKER · 4 RISK · 6 NIT)

Nothing breaks load or errors in-client: family gates are probe-first, combat paths defer, contracts are frozen and pinned, perf-critical paths are throttled/cached, suites pin behavior (not just counts) with per-lane mutation proofs. The 4 RISKs need an in-client check or a small hardening pass; none blocks the owner test session.

## Cross-client gating — CLEAN (with 1 RISK carried)

- No `st.is_mainline`-alone gates anywhere in shipped logic. main.lua:526 (`elseif st.is_mainline` autorepeat fallback) and main.lua:536 (`not st.is_mainline` + `C_EventUtils.IsEventValid` refinement) are probe-first with family fallback only where no probe API exists — correct pattern, not violations.
- Lust gate is family-derived (`st.lust_supported`, compat.lua:125), Era/UNKNOWN closed, consumed by hunter.lua:1067 and paladin.lua:1007. Paladin P2/P6/P7/CD + warrior W7 use `not st.is_retail` so Forever runs them like classic-line — matches the standing rule.
- Secret-value regime: whole-or-nothing wrappers throughout compat.lua (auras 438-480, cooldowns, power, casts, totems, attack speed) with exact no-op where the probe is absent. diag.lua:344-401 reports the regime. Clean — except R2 below.
- Twist CLEU registration classic-line-only (main.lua:555-557) is deliberate and commented; warrior dodge-window documents the same + its Forever alternative (Bloodthrill, warrior.lua:1220-1222).

## Combat-taint safety — CLEAN

- hud reflow: flip under lockdown sets `HUD.pending_apply`, applied on exit via the same `icon_effective` liveness (hud.lua:755-756, 1110-1129); `reflow_row` is layout-only (no provider calls, no `update_display` recursion) and touches only non-secure row frames — the same calls the per-tick paint already makes in combat. Pinned by hud_state §18 (combat holds 188, exit applies 150).
- Creation stays lockdown-gated everywhere (hud ensure_created, practice_ui, designmode drag guards 417/446/544, rotationtext pending_apply). No strata/parent changes in combat paths found.

## Contract integrity (parallel lanes) — CLEAN

- C2 frozen contract (compat.lua:485-534) vs consumers: hunter H2 (hunter.lua:1074-1076 id-table predicate) and paladin P3 (paladin.lua:984-986 literal-id predicate) both match the `(spell_id, name, stacks)` shape; predicate errors propagate by design (addon code, documented). Throttles: 0.5 s both (hunter `LUST_RESCAN_INTERVAL`, paladin `LUST_RESCAN_INTERVAL`).
- Pips `ST:new_pips` factory (bars.lua) vs druid call site (druid.lua:1115-1120): literals + `design` without `save`/`reset` → session-only drop, exactly the factory's documented default; no `druid_pips_x/y` keys exist repo-wide. Correctly left unwired; factory-side spec recorded for a bars follow-up.
- Design-target registry (9 targets): every registered target has a frame path; bar-relative sidebars (JotC mini-bar, CD icon group, enemy swing bar) deliberately unregistered (move with the bar overlay) — audited, no gap.
- Option keys vs consumers: 27 + 4 warrior slot toggles all verified end-to-end (options-grade §3, followup §1). Warrior `hud_show_rend/ms/bladestorm/raging_blow` flow through `hud_slot_*` (warrior.lua:2392-2396) → `show_key` → `icon_should_show`, defaults `true` = no visible change.

## Per-tick performance — CLEAN

- `ST:update_zones` reuses one ctx table, no-op read when zero zones registered. Guide computes into reused `ui.inputs/out` tables (guide-design §3). Shaman weave row caches icon texture + cast-time value (shaman-weave §1). Exactly-once provider pin holds (hud_state §5). Aura costs: P3/H2 lust scans 0.5 s-throttled; shaman FS/SS share one 0.05 s-throttled target walk; paladin `parse_seals` full walk is event-driven (aura change / swing land), not per-frame. No per-frame allocation introduced in hot paths.

## Test-honesty — CLEAN (with noted limits)

- Reconcile true-ups (bars_state 12, hud_state 4 + reflow widths 302→226) move counts with rationale + mutation proofs; behavior pins intact (family gates bars_state:2271-2384, twist/weave markers, glow latches). No weakened behavior pin found vs pre-round baselines.
- Every lane carries mutation proofs on /tmp/opencode copies with byte-identical restores. Honest limits disclosed per CAIRN two-proofs rule: everything is "verified offline", in-client behavior UNCONFIRMED in every report.

## RISKS (fix direction; none blocks the test session)

**R1. Anniversary CLEU localized-name payloads vs numeric-only CLEU matching.** competitor-scan §1.1 (single-source page-text claim, UNCONFIRMED): Anniversary sends localized spell names where classic sends numeric ids. If true, two handlers silently die on the TBC client: paladin `SPELL_DAMAGE` success (`type(sid) == "number"`, twist.lua:70 via paladin.lua:596-602) and warrior `SPELL_MISSED` special-ability OP (`hs_ids[spell_id]/cleave_ids[spell_id]`, warrior.lua:1240-1244). (`SWING_*` branches compare event/missType strings — unaffected; `SPELL_EXTRA_ATTACKS` uses tonumber — position-stable.) Paladin seal aura matching is id-only (paladin.lua:311-351) unlike the druid/warrior/shaman localized-name fallbacks, but `UnitAura` is a separate API (numeric on classic-line) — checked, not implicated. Fix: in-client check first (`/dump` the spellId slot type on Anniversary); if strings, add localized-name fallback tables resolved via `GetSpellInfo` (same pattern as warrior target-debuff bars, warrior.lua:1038).

**R2. Secret-hole scan truncation in `scan_player_aura`.** compat.lua:507-534 `break`s at the first nil-name entry; secret entries degrade to nil (compat.lua:438-480), so one secret HELPFUL aura above Bloodlust truncates the scan → H2/P3 miss a live lust window on secret-regime clients. Fix: iterate the full 1..40 cap without early break (identical worst-case cost — 40 `UnitAura` calls already), treating nil as "no match at this index". Same hole shape does not affect target-debuff scans that already continue past nils (verify per-consumer when hardening).

**R3. Paladin twist attempt/success chain is CLEU-only → silently inert on Forever.** main.lua:555-557 never registers CLEU on mainline; the attempt arms solely in the CLEU `SWING_DAMAGE` branch (paladin.lua:569-593); P1 live score/sounds/counters never fire on Forever while the twist band + next-action guide show normally. Architecturally consistent with "Twist of Light NOT probed" (paladin.lua:114-123), and the paladin report claims Forever parity only for P2/P6/P7/CD (buildout_paladin §"Forever family") — but no report states the P1-on-Forever behavior, so the owner will meet a 0/0 badge with no explanation. Fix: gate the P1 badge on CLEU availability (hide or show "classic-line only" state on Forever) or record the limitation in the widget copy.

**R4. Lust-gate nil-semantics mismatch between the two consumers.** hunter.lua:1067 (`if st.lust_supported and ...`, nil→off) vs paladin.lua:1007 (`~= false`, nil→scan-on). In-tree compat.lua always sets a boolean, so this diverges only under foreign/old sandboxes — but the frozen-contract doc (compat-bl §2) should name one rule. Fix: standardize both on `st.lust_supported == true` (closed-on-unknown) in a touch-up.

## NITS (defer with rationale)

- **N1. Doc matrix lag:** README.md:66, TESTING.md:16, CHANGELOG.md:8 still advertise Retail as 120100-only; AGENTS.md:45 + both tocs + toc_check.lua:266-267 carry 120100+120105 (owner-confirmed 12.1.5). Update the three lines to `12.1.x (120100, 120105)`.
- **N2. Stale comments:** bars_state.lua widget-breakdown comments lag the new counts (self-flagged by reconcile §2 NOTE); refresh in a touch-up, pins-only scope held correctly.
- **N3. `hunter_multi_target` ships a visible toggle with no consumer** (H3 engine is a future round; options-grade row 15 + options §2 document it as deliberately inert, nil=off). Either wire the engine round or append "(future)" to the widget copy so it doesn't read as broken.
- **N4. `sor_forever_ids` empty + Twist of Light/Holy Strike unprobed** (paladin.lua:82-123): documented plug-in point with in-client id check owned — keep tracked, no action.
- **N5. `post_lust_debuff_ids` (57723/57724) registered UNCONFIRMED, zero consumers** (only compat.lua:134 + smoke pin): correct as reference data; no caller may hard-depend (compat.lua:127-134 states the rule). No action.
- **N6. Parallel-lane harness interference:** options-followup caught transient cross-lane fails mid-pass (final 35/0). Process already requires quiescent re-runs; no action beyond keeping the rule.

## In-client checklist for the owner session (distilled from all lanes)

Twist success + JotC refresh cadence on Anniversary (also settles R1); lust-window narrowing under real Bloodlust (P3) + Steady-spam cue (H2); TF/Berserk liveness/glow, Mangle runeless-Era hide + row reflow, combat-exit deferred reflow; weave 2-3-stack markers + clip state + Flurry ICD on a live swing; aimed-shot re-point, hunter cast zone, warrior bank/SB/Shout badges; practice panel reset button + timeline drag/close; design-mode drops on practice_rotation/timeline targets; enemy-swing bar on a hostile target (classic-line only); Retail stand-in stays inert with one-time notice; `/st diag` secret-line on Retail/Midnight (also informs R2).

## Hands-up / ledger notes

HU-4 closed resolved-by-fix (verified: glow pin passes). HU-1..HU-3 deferrals stand (no #27 range helper, no hunter icon-group duplication, P2/CD-group coexistence — all honored in the tree). No new hands-up raised: R1/R2 are evidence-graded risks with stated checks, not desk disagreements.

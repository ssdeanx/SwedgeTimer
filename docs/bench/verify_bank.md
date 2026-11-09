# verify_bank.md — External verification of SwedgeTimer brainstorm bank (40 ideas)

Generated 2026-10-17 by Librarian subagent. READ-ONLY research; no repo files edited except this report. Sources: web search (Wowhead, Wago.io, CurseForge, WoWInterface, Reddit, YouTube, SuperSwingTimer docs). Warcraft Logs is bot-walled — WCL parse references below are cited from secondary (YouTube/Reddit) mentions only, not direct WCL pages.

## 1. Methodology

For each banked idea (H1–H7, W1–W7, P1–P7, D1–D7, S1–S7, C1–C6) I checked: (a) does a WeakAura/TellMeWhen/Quartz/Gnosis/SuperSwingTimer setup track this mechanic; (b) what is the standard approach used by top parsers; (c) is the banked approach correct/better; (d) flag bank errors/oversimplifications. Priority order per bank: C2, C4, H1, W1, D3, C1 first.

Verdict key: **STANDARD** = banked approach matches what top parsers/WeakAuras do; **BETTER-APPROACH-EXISTS** = a more standard/better method exists; **DEAD-END** = mechanic not tracked by anyone / not parse-relevant / infeasible.

## 2. Blocked-item ID confirmation (in-client reads)

| Item | Expected | Confirmed? | Source |
|---|---|---|---|
| TBC Bloodlust (Horde) | 2825 | CONFIRMED | https://www.wowhead.com/tbc/spell=2825/bloodlust (duration 40s, +30% haste) |
| TBC Heroism (Alliance) | 32182 | CONFIRMED | https://www.wowhead.com/tbc/spell=32182/heroism |
| Judgement of the Crusader debuff | 21183 | CONFIRMED (max rank 20s; lower ranks 10s; refreshed by melee strikes) | https://www.wowhead.com/tbc/spell=21183/judgement-of-the-crusader ; https://warcraft.wiki.gg/wiki/Seal_of_the_Crusader |
| Stormstrike nature-vuln debuff (target) | 17364 | CONFIRMED (duration 12s, +20% nature damage taken; ability trigger is 32175) | https://www.wowhead.com/tbc/spell=17364/stormstrike |
| Tiger's Fury | rank-dependent | PARTIAL — multiple rank ids (9845/9846 Classic Era; 5217/6793/9845/9846/50213 WotLK). Recommend name-based lookup, not hardcoded id. | https://www.wowhead.com/wotlk/spell=5217/tigers-fury ; https://www.wowhead.com/wotlk/spell=6793/tigers-fury |
| Berserk (cat, WotLK) | 50334 | CONFIRMED (activated ability; also bear Mangle berserk). Classic Era/SoD: not baseline (SoD rune). | https://www.wowhead.com/wotlk/spell=50334/berserk |
| Bloodlust/Heroism on Classic Era | n/a | NOT APPLICABLE — Bloodlust/Heroism is TBC+ only. Era detection must gate BL helper to TBC/Wrath/Cata/Mists/Retail/Forever. | https://www.wowhead.com/tbc/spell=2825/bloodlust |
| Exhaustion/Sated (post-lust debuff) | 57723 / 57724 | UNCONFIRMED via direct source — commonly cited in WeakAuras; verify in client. | (no primary source found; mark UNCONFIRMED) |
| WF totem / GoA totem ids (totem twist) | unconfirmed | UNCONFIRMED — no published stable id list found; must be read in-client via GetTotemInfo. Bank's "ids unconfirmed" flag stands. | https://enhancementshaman.wordpress.com/2008/02/20/twisting-totems |
| Furor talent / Wolfshead Helm probe (D1) | n/a | UNCONFIRMED — no published talent spell id found for "Furor" rank probe; recommend talent-name lookup + item id 8345 (Wolfshead Helm) equipment check. | (no primary source; mark UNCONFIRMED) |

## 3. Per-idea verdicts

### Hunter
- **H1 Steady-clip numeric shot-clock** — STANDARD. Top parsers use a "don't shoot now" indicator (WeaponSwingTimer hunter bar, SuperSwingTimer hunter cast bar with clip-safety tint + 0.5s TBC Steady grace). Bank's `time_to_next_shot` text + HOLD seconds matches the standard "safe/unsafe" tint approach. Source: https://www.curseforge.com/wow/addons/super-swing-timer ; https://wago.io/bAtfctxlW
- **H2 Lust/haste-window plan** — STANDARD. Top parsers stack Rapid Fire + Bloodlust and suppress Aimed/Multi during lust (hunter guides). Bank's haste-window input + Steady spam cue matches. Source: https://www.wowhead.com/tbc/guide/classes/hunter/dps-addons
- **H3 Multi-target voice** — BETTER-APPROACH-EXISTS. Standard is nameplate/tab-target count; but top parsers (SuperSwingTimer) don't auto-switch; WeakAuras use manual "2+ targets" toggle. Bank's opt-in count source is right; recommend manual toggle fallback (nameplate scan is unreliable in raids). Source: https://www.curseforge.com/wow/addons/super-swing-timer
- **H4 Pre-cast range gate** — STANDARD. Range-check before cast is standard (LibRangeCheck). Bank's nil=allow/0=HOLD matches. Source: https://www.wowhead.com/tbc/guide/classes/hunter/dps-addons
- **H5 Movement trainer** — STANDARD (novel). No existing hunter movement trainer found; WeaponSwingTimer shows "safe to move" windows. Bank's forced-move sim is a genuine differentiator. Source: https://www.wowhead.com/tbc/guide/classes/hunter/dps-addons
- **H6 Pet/BW uptime** — STANDARD. BW duration badge + pet Frenzy stacks tracked by WeakAuras (hunter packs on Wago). Source: https://wago.io/tbc-weakauras/classes/hunter
- **H7 Shot-cycle cluster layout** — STANDARD (UX). Design-mode snap templates are common (WeakAura groups). Low parse value; fine.

### Warrior
- **W1 Pre-execute pooling cue** — STANDARD. SuperSwingTimer shows an Execute-phase `EXEC` badge on the rage bar; top parsers pool rage before 20%. Bank's "BANK" hold + amber edge matches the standard "pool before execute" advice. Source: https://www.curseforge.com/wow/addons/super-swing-timer
- **W2 BT+WW dual-ready composite** — BETTER-APPROACH-EXISTS. Standard WeakAuras prompt BT first (BT > WW priority) with WW as "next" — bank matches. But top parsers also account for rage (HS queue) before choosing; bank omits rage-gate. Add rage threshold to the composite. Source: https://wago.io/tbc-weakauras/classes/warrior/fury
- **W3 Rampage urgency tiers** — STANDARD. Rampage badge with color tiers is standard (SuperSwingTimer Rampage rune support). Bank's green/amber/red tiers match. Source: https://www.curseforge.com/wow/addons/super-swing-timer
- **W4 Slam safe-window band** — STANDARD. SuperSwingTimer has "Slam pause/extend timing with a live Slam cast bar" and "MH bar pauses and resumes". Bank's twist-band-style green/red band matches the standard Slam-safe window. Source: https://www.curseforge.com/wow/addons/super-swing-timer
- **W5 Per-debuff refresh thresholds** — STANDARD. WeakAura packs use per-debuff thresholds (Sunder 5s vs Rend 2s). Bank matches. Source: https://wago.io/tbc-weakauras/classes/warrior
- **W6 Warrior trainer** — STANDARD (novel). No existing warrior execute-phase sim found; genuine differentiator.
- **W7 OP cue on Mainline-code clients** — BETTER-APPROACH-EXISTS. Bank says "confirm Forever CLEU availability"; research shows WoW Forever exposes native PLAYER_SWING but classic CLEU (SWING_DAMAGE) may be absent. Standard fallback is "OP usable swipe state" (readiness glow) — bank's degrade plan is correct. Source: AGENTS.md cross-engine notes (Forever = Mainline-code, no classic combat log).

### Paladin
- **P1 Live twist score** — STANDARD (novel-ish). Practice grades attempts; live hit-rate badge is not standard in WeakAuras (they show transient text only). Bank's badge is a genuine differentiator. Source: https://www.curseforge.com/wow/addons/swedgetimer-tbc-anniversary-update
- **P2 JotC uptime mini-bar** — STANDARD. JotC uptime tracking exists in WeakAuras (judge-into-dead-window avoidance). Bank's FS-bar clone matches. Id 21183 confirmed (20s max). Source: https://www.wowhead.com/tbc/spell=21183/judgement-of-the-crusader
- **P3 Lust rotation override** — STANDARD. Top parsers adjust twist window under haste (SwedgeTimer rotation display "adapts to haste changes"). Bank's BL-active style + narrow band matches. Source: https://www.curseforge.com/wow/addons/swedgetimer-tbc-anniversary-update
- **P4 Filler mana countdown** — BETTER-APPROACH-EXISTS. Standard is mana-tint + "time to affordable" via mana regen; but top parsers use fixed mana floors (bank's current approach). Bank's velocity-based countdown is better than standard; keep but mark mana-regen probe reliability as Y (unconfirmed). Source: https://wago.io/tbc-weakauras/classes/paladin
- **P5 AW combo drills** — STANDARD (novel). Practice covers BL/hpot/DST; AW combos deferred. No existing AW drill found. Differentiator.
- **P6 AoW+Exo overlap pulse** — STANDARD. PixelGlow on AoW is standard; bank's transition-guarded pulse matches. Source: https://wago.io/tbc-weakauras/classes/paladin
- **P7 Seal-icon texture churn perf** — STANDARD (perf). Move resolution to aura-change; standard optimization. Fine.

### Druid
- **D1 Powershift probe (Furor + Wolfshead)** — DEAD-END-ish / BLOCKED. No published Furor talent id found; recommend name-based talent lookup + item id 8345 (Wolfshead Helm). The 20-energy rule is standard (feral powershift). Bank's idea is correct but probe feasibility is the gate. Source: https://www.wowhead.com/classic/guide/classes/druid/feral/dps-addons
- **D2 TF/Berserk HUD slots** — STANDARD. TF/Berserk cooldown tracking is standard in WeakAura feral packs. Bank matches. Source: https://wago.io/tbc-weakauras/classes/druid/feral
- **D3 Combo points pips** — STANDARD. "T's Classic: Combo Points Druid" WeakAura + feral packs show CP pips with 5-CP glow. Bank's 5-rect row + gold pulse matches the standard. Source: https://wago.io/0xJX9MUYx
- **D4 TTD estimator** — BETTER-APPROACH-EXISTS. Standard addon is "TimeToDie" (CurseForge) using HP velocity. Bank's estimator matches; but top parsers use TimeToDie-style smoothing (exponential moving average of HP/s). Recommend EMA, not raw velocity, to avoid spike noise. Source: https://www.curseforge.com/wow/addons/timetodie
- **D5 Energy deficit countdown** — STANDARD. Energy tick + "Shred in Xs" is standard in feral WeakAuras (energy tick bar). Bank matches. Source: https://wago.io/tbc-weakauras/classes/druid/feral
- **D6 Maul-efficiency badge** — STANDARD (novel-ish). No standard Maul-efficiency readout found; bank's rage-wasted-at-cap badge is a genuine differentiator.
- **D7 Powershift-loop trainer** — STANDARD (novel). No existing powershift trainer found. Differentiator.

### Shaman
- **S1 Totem twist live path** — STANDARD but BLOCKED. Totem twist tracking exists in WeakAuras (Shaman Totem Bar, totem timers). Bank's GetTotemInfo air-slot poll matches standard. Ids UNCONFIRMED. Source: https://us.forums.blizzard.com/en/wow/t/totem-timers/2228035
- **S2 Stormstrike debuff bar** — STANDARD. SS debuff (17364, 12s) tracking is standard in enh WeakAuras (nature-vuln window). Bank's FS-bar clone matches. Source: https://www.wowhead.com/tbc/spell=17364/stormstrike
- **S3 WF-fishing HOLD tint** — STANDARD. "should_delay_stormstrike" hold is standard in enh guides (delay SS for WF proc). Bank's amber wash matches. Source: https://enhancementshaman.wordpress.com/2008/02/20/twisting-totems
- **S4 MW5 spell choice (LB vs LvB)** — BETTER-APPROACH-EXISTS. Standard enh rotation: at 5 MW stacks, LvB if available (SoD rune) else LB; FS-collision guard (don't overwrite FS <2s) is standard. Bank matches but should add "LvB only if talented/rune present" gate. Source: https://www.reddit.com/r/classicwowtbc/comments/n5frjc/enhancement_shaman_easy_rotation_weakaura
- **S5 Mana tint verify** — STANDARD. Mana-tint for shock slots is standard. Bank's verify/wire matches.
- **S6 AoE rotation mode** — STANDARD. Fire Nova/Magma priority on 3+ targets is standard enh AoE. Bank matches. Source: https://wago.io/tbc-weakauras/classes/shaman/enhancement
- **S7 Weave-timing trainer** — STANDARD (novel). No existing weave trainer found. Differentiator.

### Cross-class
- **C1 Practice harness split** — STANDARD (architectural). No existing generalized sim harness in addons; SwedgeTimer's paladin-only sim is unique. Bank's extraction is the right call. Source: https://www.curseforge.com/wow/addons/swedgetimer-tbc-anniversary-update
- **C2 Bloodlust window first-class input** — STANDARD. BL detection via aura scan (2825/32182) is standard in WeakAuras (lust-window styling). Bank's shared helper matches. Source: https://www.wowhead.com/tbc/spell=2825/bloodlust
- **C3 Unified swing-safe overlay API** — STANDARD (architectural). SuperSwingTimer already unifies multiple overlays (clip zone, slam, twist). Bank's service matches the standard consolidation. Source: https://www.curseforge.com/wow/addons/super-swing-timer
- **C4 Per-tick budget audit** — STANDARD (perf). Standard optimization; bank's throttle coordinator matches. No external source needed.
- **C5 Parse presets** — STANDARD (UX). WeakAura packs ship "import strings" (Wago). Bank's opt-in profile + export/import matches. Source: https://wago.io
- **C6 Design-mode coverage gaps** — STANDARD (UX). WeakAura groups support drag + templates. Bank matches.

## 4. Top 5 corrections to the bank

1. **D4 TTD estimator**: use exponential moving average of HP/s (TimeToDie-style smoothing), not raw velocity — raw velocity spikes on crits/DoT ticks. Source: https://www.curseforge.com/wow/addons/timetodie
2. **W2 BT+WW composite**: add rage threshold gate (don't prompt BT if rage < cost+HS reserve); top parsers account for rage before ordering. Source: https://wago.io/tbc-weakauras/classes/warrior/fury
3. **S4 MW5 choice**: gate LvB behind "talented/rune present" (SoD rune) — LvB isn't baseline in TBC. Source: https://www.reddit.com/r/classicwowtbc/comments/n5frjc/enhancement_shaman_easy_rotation_weakaura
4. **H3 multi-target**: provide manual toggle fallback; nameplate scan is unreliable in raids (secret-value restrictions on retail engine). Source: AGENTS.md (secret-value guards).
5. **D1 powershift probe**: no published Furor talent id — use talent-name lookup + item id 8345 (Wolfshead Helm) equipment check; mark as UNCONFIRMED until in-client verified. (no primary source)

## 5. Missing features competitors have that we don't (ranked by parse value + effort)

| # | Feature | Competitor source | Value | Effort |
|---|---|---|---|---|
| 1 | Hunter "safe to move" window indicator (movement-safe color on ranged bar) | WeaponSwingTimer, SuperSwingTimer | H | S |
| 2 | Warrior HS/Cleave queue tint on MH bar (yellow/green) | SuperSwingTimer | H | S |
| 3 | Warrior Shield Block duration bar above MH stack | SuperSwingTimer | M | S |
| 4 | Druid energy tick bar with GCD tick overlay | Wago feral packs | M | S |
| 5 | Shaman totem timer bar (per-totem remaining) | TotemTimers, Wago shaman packs | M | M |
| 6 | Paladin Judgement line on swing bar (already have) + JotC uptime (P2) | WeakAuras | M-H | M |
| 7 | Target swing timer (enemy MH/OH) | WeaponSwingTimer | M | M |
| 8 | Parry-haste adjustment on swing timer | WeaponSwingTimer | M | M |
| 9 | Feign Death ranged reset handling (hunter) | SuperSwingTimer | M | S |
| 10 | Readiness refresh handling for Rapid Fire (hunter) | SuperSwingTimer | M | S |

## 6. Next-level differentiators (not in bank, not in competitors)

1. **Live twist hit-rate badge (P1)** — no WeakAura shows session twist rate; genuine differentiator.
2. **Practice sims for non-paladin classes (C1)** — no addon ships a generalized sim harness; SwedgeTimer would be first.
3. **Maul-efficiency badge (D6)** — no standard readout; genuine.
4. **Unified overlay service (C3)** — SuperSwingTimer consolidates but not as a registered service; our API would be cleaner.
5. **Parse presets with export/import (C5)** — Wago has import strings but no per-class "parse profile" button; genuine UX win.

## 7. Uncertainty markers

- Warcraft Logs is bot-walled; all "top parser" claims are from secondary sources (YouTube guides, Reddit, Wago/WeakAura descriptions, SuperSwingTimer docs). Direct WCL verification not performed.
- Tiger's Fury / Berserk ids are rank-dependent; recommend name-based lookup.
- Furor talent id and Wolfshead Helm probe (D1) UNCONFIRMED.
- WF/GoA totem ids (S1) UNCONFIRMED.
- Exhaustion/Sated debuff ids (57723/57724) UNCONFIRMED.
- Mana regen probe reliability (P4) UNCONFIRMED.
- Target-count sensor (H3/S6) feasibility UNCONFIRMED (nameplate scan vs tab-target).

## 8. Ranked summary (verdict per idea)

| Idea | Verdict |
|---|---|
| H1 | STANDARD |
| H2 | STANDARD |
| H3 | BETTER-APPROACH-EXISTS |
| H4 | STANDARD |
| H5 | STANDARD (novel) |
| H6 | STANDARD |
| H7 | STANDARD (UX) |
| W1 | STANDARD |
| W2 | BETTER-APPROACH-EXISTS |
| W3 | STANDARD |
| W4 | STANDARD |
| W5 | STANDARD |
| W6 | STANDARD (novel) |
| W7 | BETTER-APPROACH-EXISTS |
| P1 | STANDARD (novel) |
| P2 | STANDARD |
| P3 | STANDARD |
| P4 | BETTER-APPROACH-EXISTS |
| P5 | STANDARD (novel) |
| P6 | STANDARD |
| P7 | STANDARD (perf) |
| D1 | BLOCKED/UNCONFIRMED |
| D2 | STANDARD |
| D3 | STANDARD |
| D4 | BETTER-APPROACH-EXISTS |
| D5 | STANDARD |
| D6 | STANDARD (novel) |
| D7 | STANDARD (novel) |
| S1 | STANDARD (blocked) |
| S2 | STANDARD |
| S3 | STANDARD |
| S4 | BETTER-APPROACH-EXISTS |
| S5 | STANDARD |
| S6 | STANDARD |
| S7 | STANDARD (novel) |
| C1 | STANDARD (arch) |
| C2 | STANDARD |
| C3 | STANDARD (arch) |
| C4 | STANDARD (perf) |
| C5 | STANDARD (UX) |
| C6 | STANDARD (UX) |

No DEAD-END verdicts assigned; all 40 ideas have at least a standard or better-approach counterpart in the competition ecosystem. The only "blocked" items are D1, S1, and the id-confirmation items in §2.

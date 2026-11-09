# Live in-game test script — Classic Era/SoD (11509) + TBC Anniversary (20506) — 2026-10-19

Operator-run. READ-ONLY scope: no addon file is authority here; the game client is.
Every numbered expectation cites the sim audit (or source) it came from. Anything
without a citation is marked **OBSERVE-and-report** — record what happens, change nothing.

- Version under test: **2.1.1** (all 7 tocs + main.lua). Confirm at top of `main.lua` / TOC before starting.
- Clients in scope: **Classic Era / SoD `11509`** (vendored `LibClassicSwingTimerAPI`)
  and **TBC Anniversary `20506`** (same engine). Wrath/Forever/Retail rows from the
  audits are NOT re-tested here (noted where a rule is shared).
- Preconditions per `TESTING.md`: back up `WTF/` + addon folder; `/console scriptErrors 1`.
- Guides show unless their toggle reads exactly `false` (`nextaction_enabled ~= false` shows;
  `== false` hides — `nextaction_ui.lua:441`, the guide's `should_show`). All six guides now
  ship **ON** by default, so **turn the other five off** before you read one class's prompts
  (`/st` → class section → `nextaction_enabled`), and check the toggle before you read a
  prompt as a defect.
- HUD toggles are `hud_show_<slot>` per slot (one per class HUD slot —
  `option_tables.lua:1349`, the per-class slot lists from `:4095` on; the template select
  writes the same keys at `:1866-1869`).
- Validation owner: orchestrator.

**Extended 2026-10-20** in the Phase-8 documentation truth pass
(`bench/final_completion_plan_2026-10-19.md` Phase 8). What changed:
- **§7 is new** — the practice surfaces: the rotation scenario per class, every class's
  focused drill list, the level badge + XP bar, the Progress page, the stats frame and
  its accuracy sparkline, and the design-mode element list.
- **Three class rows that had gone stale are corrected** (the CoE slot, the Serpent target
  read and the Wolfshead probe all LANDED — they were written when those items were
  filed): §3.5 (shaman CoE), §4.2 (hunter Serpent), §5.3 (druid Wolfshead), plus a new
  §1.8 (paladin Forever ids).
- **§9's ID table gained six rows** — the Still-UNCONFIRMED list for the wave: 66842 +
  the water-totem read on 3.80.2, the Wolfshead read, the Serpent target read, the three
  Forever ids, the Slam cast-time read on a name-only TBC client, and the warrior HS-queue
  drill (**not shipped** in this build).
- The trailing harness state was refreshed to the tree's current 41/0.
- The old §7/§8/§9 are now §8/§9/§10; the internal cross-references were updated.

**Extended again 2026-10-20 (the APL utility layer + the scenario-surface fixes).** The tree
moved on after the Phase-8 pass; this script now describes the build that exists. What changed:
- **§7.2 gained the utility rows, the hold contract and the row's hygiene** — the rotation
  scenario now carries the class's **full** sim priority list, not just the damage rows.
- **§7.3 gained the pick channel, the session routing and the pre-pull drills**, and its drill
  sets are corrected: the **warrior ships six** drills now (the queue drill and the pre-pull
  opener were added), and the **paladin's list leads with the twist timing drill**.
- **§7.9 and §7.10 are new** — the **pre-pull phase** (each class's own pre-pull table and
  drill) and the warrior's Heroic Strike / Cleave **queue drill**: run it and record its feel.
- **P8-6 is corrected** — the HS/Cleave queue drill **shipped** on 2026-10-20. The old row
  said "NOT SHIPPED in this build"; that was wrong and the row now says what to test.
- **§9 gained the P9 rows** — the wave's still-UNCONFIRMED list (seven items).
- **§1's client scope is unchanged** (Era/SoD + TBC); the Wrath/Forever/Retail-only rows are
  noted where they apply, as before.

**Extended a third time 2026-10-20 (the audit-fix wave).** Six defects from the
post-everything deep audit landed after the last docs pass. What changed:
- **§7.11 is new — the logout-persistence check.** Run a session, **log out**, log back in,
  and read the run counter, the time active, the history row and the daily streak off the
  Progress page. It also carries the **reload caveat**: a UI `/reload` fires no
  `PLAYER_LOGOUT` and writes no SavedVariables, so a mid-session reload loses the session
  record whatever the addon does — **log out instead of reloading** to test persistence.
- **§7.12 is new — the mid-session reset check.** Reset the Progress page while the session
  is still running, then grade another attempt: the XP, the streak and the stats must be
  recorded again, and the badge must show only the post-reset XP.
- **§5.6 is new — the bear chain's queued Maul is a HOLD.** In bear form with a Maul
  queued, the scenario must show the hold (the guide's `RIDE`) and offer **no "ride"
  button**; pressing nothing must read HOLD OK and record **no attempt** (no points for
  idling), and pressing anything must read ILLEGAL CAST and grade F.
- **§1.9 is new — the paladin's practice strip per family.** The TBC strip must offer no
  "Hammer of Wrath" button the TBC rotation can never ask for.
- **The stale "the druid states no hold at all" line in §7.2 is corrected** — the druid has
  exactly one press-nothing hold (the bear's queued Maul); its other nine guide holds name
  a spell to press and stay actions.
- Sources: `bench/druid_hold_ride_2026-10-20.md`, `bench/practice_persist_2026-10-20.md`,
  `bench/paladin_audit_close_2026-10-20.md`.

**Extended a fourth time 2026-10-20 (the documentation-truth pass).** The docstruth audit
(`desks/docstruth-audit/journal.md`, VERDICT: FINDINGS 18) compared every claim in this file
against the tree. This pass corrects the claims that did not match the build. What changed:
- **§0 step 2 is now the whole `/st diag` block.** There is **no** `/st diag verbose` command:
  the slash handler matches only `` / `practice` / `design` / `diag` (`main.lua:2013-2046`), and
  `/st diag` *is* the verbose report. The old step 3 sent the operator after a command that does
  not exist, so the highest-value paste of the session was lost. The old step 3 is folded in.
- **§0 step 3 is new — the usable-only trinket gate** (a passive stat stick must not render; an
  on-use trinket must render and count down; an unreadable effect must hide).
- **§2 step 6 is new — the warrior's W-21 HUD mirror** (the Sunder upkeep slot on the TBC row).
- **§6.1 no longer asks the operator to confirm the ABSENCE of a rogue SnD prompt.** The build
  ships an ARMED SnD upkeep; the step now states the shipped contract.
- **§6.2 / §7.9 carry the tree's current names** — the rogue's Forever pre-pull is Blade Flurry
  13877 @-2, and the builder chain is `{Saber Slash, Mutilate, Hemorrhage}` with a family gate.
- **§7.2's paladin paragraph is no longer "the utility layer was still landing"** — it landed:
  the paladin's rotation table carries **17** rows.
- **§7.8's design-target count is class-dependent** — 13, or **14 on a druid**.
- **§7.9's pre-pull rows are the tree's rows** — the hunter's table has no Era list, the paladin's
  table carries **11** rows, and 10301's name is CONFIRMED (Retribution Aura).
- **§8 / §9's file:line citations were re-pointed at the tree** (the WANTED_IDS table, the error
  ring, the rogue slot table, the JotC bar, the hunter's steady rank, the delay budget, the
  template preview).
- **The U11 row's JotC claim is marked web-CONFIRMED, not in-client.**
- Everything marked "verified against the tree 2026-10-20" was re-read in the tree on that date.
  **Nothing this pass added claims in-client proof** — the rows it touched stay UNCONFIRMED, and
  the operator-CONFIRMED rows the corpus already carried (e.g. Blood Frenzy 412507) are left
  exactly as they were.

**Extended a fifth time 2026-10-20 (the per-client truth pass's operator probes).** The
per-client truth pass (`bench/perclient_truth_final_2026-10-20.md` §6) handed over four
probes no offline pass could close. What changed:
- **§1 steps 10–11 are new** — the **Consecration icon press** (the HIGH-1 canonicalisation
  fix, in-client) and the **Cata/Mists Seal of the Crusader** row (MEDIUM-2).
- **§3 step 8 is new** — the **Cata/Mists shaman common abilities** row (MEDIUM-1).
- **§9's P12 row is new** — the id-form/arity probe, the name-form probe, the Cata/Mists
  Healthstone probe and the **HUD slot ownership** (the hunter's slot set per client);
  §4's setup line points at it.
- **§10 asks for the four answers by name** (one block, at the end of the report-back).
- **The P9 / P10 labels collide**: §9's own "P9 rows" / "P10 rows" tables are the APL
  utility layer and the audit-fix wave; the truth pass's P9–P12 are the four probes above and
  every row here carries its source tag.
- **Nothing added here claims in-client proof** — the four probes are **UNCONFIRMED in-client**
  until the operator runs them.

## 0. Step 0 — every client, every login (2 min, both clients)

1. Log in. Expect no Lua error, bars on screen. The addon prints its **login one-liner** by
   itself at login (the `family=… iface=… version=… engine=… lrc=… lcd=… ldb=… guides=…`
   line, `main.lua:673-677`) — record it verbatim.
2. Run **`/st diag`** and record the **whole block** — it is the verbose form: the login line
   again, then the `flags`, `modules`, **`ticks`** and `secrets` lines, then the wanted-id lines,
   then the error-ring lines, and finally the `diag runtime …` counters line
   (`diag.lua:681-709`, `main.lua:1947-1998`). There is **no `verbose` sub-command** — the slash
   handler matches only `` / `practice` / `design` / `diag` (`main.lua:2013-2046`), so
   `/st diag verbose` prints the usage line instead of the report. **This is the highest-value
   paste of the session**: the ids section and the error ring are inside it (§8).
   Expect shape per `TESTING.md` (`family=` + `engine=vendored-lib` on both these clients;
   `lrc=fallback` is the designed fallback, not a bug; `deadline=fired` means a lib missed the
   5s window — record it).
3. **The trinket slots — the usable-only gate.** All six classes ship two trinket slots
   (`hud_show_trinket1` / `hud_show_trinket2`, on by default). A slot renders **only when the
   trinket has a usable effect** (`hud.lua:319-350,735-746`):
   - a **passive stat stick** must **NOT** render in the slot (the client's item cooldown reports
     it disabled);
   - an **on-use trinket** must render and **count its cooldown down** while it is on cooldown;
   - a **proc trinket** renders while its buff is up, then shows its internal cooldown as a
     reversed swipe;
   - an **empty** slot renders nothing, and an **unreadable** effect hides the slot — an unknown
     is never rendered as "usable".
   Swap the two trinkets and record what each slot shows.
4. `/reload`, then cast/attack within 5 seconds — expect no error (used to be a crash window).
5. Open `/st` (all sections render), `/st design` (grid toggles), `/st practice` (panel opens).
6. Run `/st diag` again — must still match.

Report back per §10: every diag line verbatim per client, every Lua error text verbatim,
pass/fail/did-not-see per visual, plus anything that *looked* wrong but printed nothing.

## 1. Paladin (Era/SoD + TBC)

Sources: `bench/paladin_rotation_audit_2026-10-19.md`, `bench/sod_paladin_variants_2026-10-19.md`,
`bench/open_rules_2026-10-19.md` §2 (fight-remaining CUT), `bench/verify_bank.md` §P2 (JotC 21183).

Setup: enable paladin guide. HUD template P-T1 "Twist Core" (cs, judgement, exorcism visible;
`bench/hud_templates_2026-10-19.md` §1).

1. **Twist window width.** Era/TBC: band appears in the last **~0.4 s** of the swing
   (audit §Cross-client MATCH: `twist.lua:38` vs classic `basic_ret.apl.json` + TBC `default.apl.json`).
   SoD: **200 ms** hard-wait (`strictSequence` cast+`wait(autoTimeToNext+200ms)`,
   `p8-twist.apl.json`; audit §SoD CONFLICT). OBSERVE-and-report the felt width per client —
   do not tune, just record.
2. **Era pair.** Expect SoC↔SoR twist (SoR seal id 21084, `classes/paladin.lua:87,152`),
   no Crusader Strike prompt (`cs_known=false` → Command tiebreak; classic sim has no CS).
   HoW cue below 20% only. Consecration single-target on Era (audit §Era MATCH).
   OBSERVE-and-report: Judgement-stopattack and prepull sequencing have NO guidance by design
   (audit §Era GAPs) — record what you do manually, not a failure.
3. **TBC pair + JotC.** Expect SoC→SoB twist. The JotC mini-bar ships **off** — turn it on
   (options → Paladin → "Judgement of the Crusader bar"; the toggle reads exactly `true`) before
   you look for it. With it on it counts **21183, 20 s max-rank**, melee-refreshed, lower ranks
   fixed 10 s, never refreshed (`classes/paladin.lua:2508-2537,2670-2688`). The 20 s / 10 s
   durations are **web-CONFIRMED** (wowhead / warcraft.wiki, `verify_bank.md` §2) — the in-client
   shape is **UNCONFIRMED**: record the two durations per client. Crusader-priority cue present.
   OBSERVE-and-report pull CS timing: our delay-budget default **0.9 s**
   (`nextaction.lua:499-504`) vs sim 11 s "Delay Major CDs" (audit §TBC CONFLICT) —
   record what the guide says in the first 11 s, do not "fix" in-client.
4. **SoD Exodin FCFS.** Expect order `exo > cs > ds > judge > cons > how`
   (`nextaction.lua:984`; `sod_paladin_variants.md` §2 MATCH). Seal-maintenance 1 s reseal +
   Judge-lift on expiry is landed in-tree (closes the old audit GAP) — confirm Judge/seal
   prompts at ≤1 s seal remaining. DS 3-stack gating needs Holy-Power input
   (aura 1226461 + set 1226460, `sod_paladin_variants.md` §1 GAP filed, zero hits in-tree) —
   OBSERVE-and-report whether DS ever withholds on stacks (expect: never withholds yet).
5. **SoD variants (only if the build ships a selector).** Seal-stacking (dual-seal,
   Judge-only-on-dual), Shockadin 1H/2H (Holy Shock 20930r3, Sunlight 1239543 / Templar 1240574,
   Aura Mastery 407624 + Libram 1214298), Wrath-like (Templar 1226464 DS-wait, T2-2pc 467518
   Judge gate) — all BUILD verdicts with APL citations (`sod_paladin_variants.md` §§3-6;
   wired per central journal row 140). Holy-Shock/AM slots + Infusion 6 s shape are FILED
   (expect absent). OBSERVE-and-report per variant: which buttons prompt, which never appear.
6. **Practice.** `paladin_twist` drill (twist sim consumer) + `paladin_aw_combo` drill
   (AW-opens-window, lag bands S≤0.2/A≤0.5/B≤1.0/C≤2.0/D; `buildout_practice_2026-10-17.md` §3).
   Run one twist session: begin → twist → stop. Enter combat mid-session → "paused"; leave →
   resumes with timers shifted, no instant expiries. The paladin's own **focused drill list**
   (FCFS priority order, Prepull seal, Judgement fit) and the paladin **rotation scenario**
   are covered in §7.
7. **Designer preview.** `/st design`: practice panel + rotation display + timeline all listed
   alongside the panel; drag each, confirm drop + persist (panel persists
   `practice_panel_x/y`; rotation/timeline session-local; `buildout_practice_2026-10-17.md` §4).
   Template preview: only cs/consecration/exorcism/wings/trinkets have scripted samples
   (`hud.lua:1120-1158` per `hud_templates.md` §0) — other slots show live state; record which.
8. **Forever ids (Echo / Holy Strike) — expect INERT until the client confirms them.**
   The two Forever id tables now carry `1311703` (Echo of Command) and `1311704` (Echo of
   Righteousness), and Holy Strike `10333` is published as a plug-in point. All three are
   **web-confirmed, client-unconfirmed and name-anchored**: an id only counts when the
   client's own resolved name matches, so on a client that answers differently the input
   stays unknown and the archived seal input stands — expect **no wrong prompt**. Record
   whether the client resolves those three names at all (see the new §9 rows).
9. **The practice strip per family — no button the rotation cannot ask for.** On **TBC**
   the paladin's practice strip must offer **no "Hammer of Wrath" button**: the TBC
   rotation can never ask for it (the engine's execute arm is Era/Forever only), and
   pressing it used to grade out-of-order → F for a spell the rotation never wanted. On
   **Era** the strip's rotation part drops Consecration and Exorcism (the Era APL carries
   no filler row) — those presses stay reachable through the panel's asked-for
   vocabulary, so check that the panel still offers them when the engine asks. Record
   which rows each family's strip shows.
   Source: `bench/paladin_audit_close_2026-10-20.md` §1.1. **Verified offline,
   UNCONFIRMED in-client.**
10. **The Consecration ICON button grades CORRECT (the HIGH-1 fix, in-client).** This is the
    end-to-end confirmation of the canonicalisation fix: the panel must offer **ONE** button
    for Consecration, and a press of that button must grade **CORRECT**.
    - **Where:** the paladin **rotation scenario** (§7.2) on **TBC / Wrath / SoD / Forever** —
      the families whose rotation asks for Consecration. On **Era** the rotation carries no
      Consecration filler row (§1.9), so the step may never come: record "the step never
      appeared", which is **not** a defect.
    - **How:** set Practice mode = **Rotation scenario**, start the session, and wait for a
      step whose prompt reads `next: cons` (the prompt is `next: <key>`,
      `practice_ui.lua:5316`). Then press the **icon** button — the one carrying the
      Consecration **icon** (labelled `Consecration`). After the fix that button's key IS the
      canonical `cons`: the rotation's `cons` and the guide slot's `consecration` are ONE
      button and the icon rides it (`bench/grader_seam_2026-10-20.md` §2.1).
    - **Expect:** the panel reads **CORRECT** and the step advances; the status line reads
      `correct: cons` (`practice_ui.lua:5177`).
    - **A defect is any of:** the status line reads
      `out of order: wanted cons, cast consecration` — the pre-fix string
      (`practice_ui.lua:5187`), and that exact line means HIGH-1's fix did not reach this
      client; **or** the panel reads **OUT OF ORDER** / grades **F** for a press of the
      panel's own Consecration button; **or** the panel shows **two** Consecration buttons (a
      bare text `cons` AND an icon `consecration`) — the pre-fix panel; **or** the Consecration
      button carries **no icon** (the label alone) — the pre-fix icon lookup.
    - **Report:** the exact grader line, the button labels as you saw them, and the client.
    - **Verified offline, UNCONFIRMED in-client** (`bench/grader_seam_2026-10-20.md` §6;
      source: `bench/perclient_truth_final_2026-10-20.md` §6 **P9**).
11. **The Seal of the Crusader button is NOT offered on Cata/Mists (MEDIUM-2, in-client).**
    - **Where:** a **Cata (4.3.4) or Mists (5.5.0)** client only. On **Era/SoD/TBC/Wrath/
      Forever** the seal exists and IS published — record **N/A (client out of scope)**, not
      a failure.
    - **How:** open the paladin **practice panel** and **list every offered button**; look for
      a "Seal of the Crusader" button.
    - **Expect: NO "Seal of the Crusader" button.** The spell was removed in 4.0, so the
      class's CATA and MISTS neutral buckets carry **no `sotc` key**
      (`classes/paladin.lua:4494-4522`) while their **other ten keys** stay published
      (`aw`, `hpot`, `abacus`, `stop`, `holy_light`, `flash_of_light`, `lay_on_hands`,
      `divine_shield`, `bop`, `food`).
    - **A defect is:** a "Seal of the Crusader" button in the list — the publish is not
      family-scoped; report the **full** button list. **Or** a panel that offers **none** of
      the ten other keys — the whole bucket was dropped instead of the seal. **Or** a press of
      the seal reading **NEUTRAL** — on those clients the seal press is a **mis-pick**
      (graded F), because the bucket still carries `sotc`.
    - **Report:** the full button list per client, and whether a Seal of the Crusader button
      was present.
    - **Verified offline, UNCONFIRMED in-client** (`bench/final_gate_fixes_2026-10-20.md` §2;
      source: `bench/perclient_truth_final_2026-10-20.md` §6 **P10**).

## 2. Warrior (Era/SoD + TBC)

Sources: `bench/warrior_rotation_audit_2026-10-19.md` §2 (M1–M8), `bench/open_rules_2026-10-19.md` §3
(Victory Rush HOLD DORMANT), `bench/ids_research_2026-10-19.md` §§U3/U13, central journal
rows 110/140 (rotfix + Blood Frenzy 412507 operator-CONFIRMED).

Setup: enable warrior guide. HUD W-T1 "Fury Core" (op, execute, bt, ww, hs visible;
family sets via `resolve_guide_slots`, `hud_templates.md` §2).

1. **Core numbers.** BT 30 rage / 6 s CD (M1); WW 25 rage / 10 s (M2); OP window **5.0 s** (M3);
   Execute threshold **20%** (M4); HS rank (`25286` in `hs_ids`), Cleave rank (`20569`);
   Slam 11605 swing-reset (`StopMeleeUntil(...,true)`); OP-first ordering (rule 1 before rule 2).
   Report any number that differs in-client.
2. **ww_ids fix (was HIGH G1).** Rotfix lane re-pointed `ww_ids→1680` (central journal row 110).
   Confirm WW prompts track Whirlwind 1680, never Overpower ranks. If an OP-rank icon ever
   appears in the WW slot, copy the exact prompt + report as regression.
3. **SoD Blood Surge.** Rotfix wired the SoD Blood Surge aura + HS floors (journal row 110);
   Blood Frenzy rune **412507 operator-CONFIRMED in-game 2026-10-19**. Confirm both fire
   on SoD; record the exact aura/button behavior.
4. **Victory Rush — expect NOTHING (HOLD DORMANT).** Sim never kills a target
   (`victory_rush.go` comment; both Forever APLs contain no VR line — `open_rules.md` §3).
   Our bypass is dormant wherever probes fail: the gather feeds `victory_rush` **only** on the
   Forever family, and only when the spell resolves *and* `IsSpellUsable` says usable
   (`classes/warrior.lua:3623-3641`); the engine's Execute bypass reads it at
   `warrior_guide.lua:1581-1589`.
   Checklist only: VR spell id (**34428 UNCONFIRMED for Forever**, WotLK-sourced),
   Victorious aura id/duration (no source anywhere), `IsSpellUsable` post-kill semantics —
   record all three, expect no prompt on Era/TBC either way.
5. **HS floor / OP fast path / hamstring** (rotfix + follow-up lanes, journal rows 110/133):
   HS tint at low rage (queue HS with low rage → insufficient-rage colour per `TESTING.md`);
   Blood Surge glow starts once and stops cleanly; hamstring-weave filler; Desync spark (W1).
   OBSERVE-and-report each.
6. **The W-21 HUD mirrors — the Sunder upkeep slot.** On **TBC** the warrior's HUD row is the
   six core abilities **plus the Sunder Armor mirror** (`classes/warrior.lua:4050-4056,4090-4105`),
   and the **guide** row carries the matching Sunder slot. The contract:
   - the mirror **ships off**: it is hidden unless `hud_show_sunder` reads **exactly `true`**
     (`false` and `nil` both hide — `config_presets.lua:1333-1339`,
     `classes/warrior.lua:4262-4281`). Turn it on (options → Warrior → HUD → Sunder Armor) or
     pick the **W-T2 "Full + Trinkets"** template, which switches it on;
   - once on, the icon renders and is **display-only**: Sunder has no cooldown of its own to
     ride, so the mirror **never rides the GCD swipe** and never counts a cooldown;
   - the **debuff countdown** lives on the **guide**'s Sunder icon — its swipe follows the
     upkeep window the class feeds (`classes/warrior.lua:3252-3253,3737-3747`), and the window
     is fed only on TBC/Forever. On Era/SoD expect no Sunder row at all.
   Record: whether the mirror was off until you turned it on, whether the HUD icon showed a
   swipe (it must not), and whether the guide's Sunder icon counted the debuff down.
   **Verified offline against the tree 2026-10-20, UNCONFIRMED in-client.**
7. **Practice.** `warrior_execute` drill (phase crossing at HP threshold, entry grade bands rage
   pooled at crossing = "BANK"; `buildout_practice_2026-10-17.md` §3). Feed HP by play;
   record entry grade vs pooled rage. The warrior's own **focused drill list** (core
   rotation, core window, debuff upkeep, execute burn, **the HS/Cleave queue window**,
   **the pre-pull**) and the warrior **rotation scenario** are covered in §7 (the queue
   drill is §7.10, the pre-pull phase is §7.9).
8. **Designer preview.** Same three targets as §1.7; rotation label `2/3`-style text, all four
   formats, drag + lock (`TESTING.md` WotLK pass).

## 3. Shaman (Era/SoD + TBC)

Sources: `bench/shaman_rotation_audit_2026-10-19.md`, `bench/wrath_leftovers_2026-10-19.md`
(§1 S1–S5 CONFIRMED values + §4 M1–M5 filed list; M3 CoE filed cut-with-reason),
`bench/verify_bank.md` §§S2–S4 (SS 17364 CONFIRMED 12 s; MW5 LvB-gate; S3 HOLD),
`bench/ids_research_2026-10-19.md` §U12.

Setup: enable shaman guide. HUD S-T1 "Twist Core" (SS/FS/ES/twist) then S-T2 "Full Enhance +
Weave" (all 8 + weave icons; `hud_templates.md` §5).

1. **SS never delayed (default).** Rule-7 WAIT contradicts every sim (audit §Cross-sim #1);
   rotfix closed it to **opt-in** (central journal row 114). Default: SS prompts on cooldown,
   no HOLD. Only if you explicitly enable the WAIT opt-in should a hold ever appear —
   record which setting you ran.
2. **Era: expect NO Flame Shock prompt.** Sim never casts FS on Era (mana-starved, no runes;
   audit §Era CONFLICT HIGH). Rule 5 prompting FS on runeless Era is sim-divergent —
   record every FS prompt on Era as an observation (do not "fix" in-client).
   ES mana gate (≥50%) and Searing maintain (fight >20 s) are GAPs — OBSERVE-and-report OOM
   cycling and totem behavior. No weave assist on Era (correct silence).
3. **SoD slots (built, journal row 114).** Expect prompts for Feral Spirit **440580**,
   Lava Lash **408507** (unconditional), Molten Blast **425339** (filler), Shamanistic Rage
   at mana **≤65%** (SoD threshold; TBC uses 10% — do not cross-check across clients).
   WF ICD is **1.5 s on SoD sims** vs hardcoded 3 s strip/hold (audit §SoD GAP) —
   record strip/HOLD timing feel. SS CD is **6 s on SoD** (sim flat 6 s; `wrath_leftovers.md` §1 S5);
   swipe fallback reads 10 pre-first-cast, live client length rides after — record the first-cast delta.
   MW: guide is MW5-only, sim weaves LB/LvB at ANY stacks when the cast fits —
   OBSERVE-and-report every fight where the guide stays silent while a cast would fit.
4. **TBC shape.** SS 10 s; Fire Nova **25537** 15 s CD; Magma **25550** filler (incl. overwriting
   Searing); twist cadence ~9.5–10 s (buff-keyed re-drop filed, stamp-timer shipped);
   SR at mana **<10%** (configurable 5/10/20/30 in sim); FN **suppressed while Fire Ele is out**
   (audit §TBC CONFLICT — record any FN prompt that would replace a live Fire Ele as a bug).
   Mana-pause on twisting and max-rank-twist are FILED (do not expect; record oom-in-twist).
   FS fight-≥12 s gate: sim-side UNCONFIRMED (`ids_research.md` U4) — record FS behavior in
   the first 12 s, no verdict.
5. **CoE — the slot now EXISTS (Wrath only).** The 18th guide slot (`coe`, id **66842**)
   fires on **Wrath** when the water totem (client slot 3) has under 20 s left, and a
   display-only HUD mirror glows under the same threshold (the mirror hides unless
   `hud_show_coe` reads exactly true). The rule is **Wrath-only**: on Era/SoD/TBC expect
   NO CoE prompt — report one as a bug. Both the id and the water-slot read are
   **UNCONFIRMED in-client** (see the new §9 rows): record whether the CoE icon ever
   appears on 3.80.2, whether the water totem's remaining time is readable at all, and how
   long the prompt stays up. The old "expect NOTHING" note is superseded — that
   filed cut-with-reason (`wrath_leftovers.md` §4 M3) was closed by
   `bench/shaman_coe_ss_2026-10-19.md`.
6. **Practice.** `shaman_weave` drill (marker/clip model; grade by margin before the marker,
   clip → F; `buildout_practice_2026-10-17.md` §3). Cast a LB that outlasts the swing —
   spark travels one way only, turns red on clip (`TESTING.md` Era/SoD checklist). The
   shaman's own **focused drill list** (enhancement priority, stack decision, Stormstrike
   decision, totem upkeep) and the shaman **rotation scenario** are covered in §7.
7. **HUD details.** WF ICD strip red→orange→green; FS target bar; SS/SR badges; LS charge row;
   2–3-stack weave icons in the safe-start band with effective cast times; Flurry ICD readout;
   DW SYNC/DESYNC badges (`TESTING.md` WotLK pass — same visuals on these clients).
8. **The shaman's five common abilities ARE offered on Cata/Mists (MEDIUM-1, in-client).**
   - **Where:** a **Cata (4.3.4) or Mists (5.5.0)** client only. On **Era/SoD/TBC/Wrath/
     Forever** record **N/A (client out of scope)** — those are rotation families and the
     abilities are already offered there.
   - **How:** open the shaman **practice panel** and **list every offered button**.
   - **Expect: the five common abilities are offered** — **Healing Wave**, **Chain Heal**,
     **Water Shield** (the SoD client renamed it "Mana Shield", so the panel offers whichever
     name the client knows), **Healing Potion** and **Food**
     (`classes/shaman.lua:4795-4848`, `ST.SHAMAN.practice_common_actions`).
   - **Why:** `apply_family_slots` used to return early on the families that carry no rotation
     row (Cata and Mists), so `apply_practice_panel_actions()` was never reached and the panel
     stayed narrower than the class's own `practice_panel_slots`; `ST.SHAMAN.post_init` now
     calls it itself (`bench/final_gate_fixes_2026-10-20.md` §1).
   - **A defect is:** **any one of the five missing** from the panel — the widening did not
     land (MEDIUM-1 not closed in-client). Report the **full** button list and which of the
     five you saw.
   - **Verified offline, UNCONFIRMED in-client** (`bench/final_gate_fixes_2026-10-20.md` §1;
     source: `bench/perclient_truth_final_2026-10-20.md` §6 **P11**).

## 4. Hunter (Era/SoD + TBC)

Sources: `bench/hunter_rotation_audit_2026-10-19.md`, `bench/hunter_open_2026-10-19.md`
(§§1–5 verdicts), `bench/ids_research_2026-10-19.md` §§U1/U2/U9, `bench/verify_bank.md` §§H1–H6.

Setup: enable hunter guide. HUD H-T1 "Shot Rotation" (steady, multi, aimed, kill_command;
`hud_templates.md` §3). The per-client HUD slot set — which slots exist at all — is read in
**§9's P12-d row**.

1. **Era weave.** Aimed 3 s-cast above Multi weave, both clip-gated; Raptor as melee surface
   (rules 6a/6b/7; audit §Era MATCH). Steady never prompts (no Steady in Era sim — correct
   silence). Serpent/Arcane/traps/Volley/Mongoose/Wing Clip never prompt (audit §Era GAP MEDIUM) —
   OBSERVE-and-report, not a failure. (The new Serpent target scan runs only when the client
   knows a Serpent rank; on a client that knows none, no target scan happens at all — record
   which case your client is.)
2. **SoD Chimera.** Chimera **409433** instant 6 s CD tops the ranged weave (rule 5b; audit §SoD
   MATCH). Serpent upkeep is now **fed by a real target-debuff read**
   (`inputs.serpent_active` — the name "Serpent Sting" first, the sourced rank ids second):
   a scan that runs and finds nothing withholds the naked Chimera, an **unreadable**
   debuff still allows it. The read is **UNCONFIRMED in-client** (see the new §9 rows):
   record, per client, whether the sting is readable at all, and whether the guide ever
   withholds the Chimera while the sting is actually UP (a false "down" is a defect).
   Lock and Load **415413** input
   MISSING (audit §SoD GAP MEDIUM-HIGH) — record free-shot windows the guide ignores.
   Traps/Sniper/mana: badge/tint only — OBSERVE-and-report.
3. **TBC core.** Kill Command **34026** #1 BM priority; Steady filler under clip guard;
   BW/RF as on-CD pops (audit §TBC MATCH). **Arcane Shot 27019 NEVER prompted** (audit §TBC
   GAP HIGH — TBC set has no Arcane slot/input) — confirm the absence, record filler
   sequences where sim-optimal would mix Arcane. Steady rank: sim casts **34120** (downrank);
   we resolve highest-known (`classes/hunter.lua:70-76,2044-2047`) — record the icon rank, do NOT
   change ids on this pass (audit CONFLICT LOW). Mana: Viper **34074** <5% / Hawk **27044**
   ≥25% group MISSING — record Steady-into-OOM stretches. Melee weave is sim-default;
   guide teaches turret — record weave windows the guide never cues.
4. **H2 lust branch — expect NO suppression (CUT).** Operator decision (central journal
   rows 118/120; `hunter_open.md` §5: no APL lust-branch in any fetched APL). Under live
   BL/Heroism, Aimed/Multi must NOT blanket-suppress — clip-math decides. Record Aimed/Multi
   behavior under lust verbatim; Steady-spam cue firing alone under lust = regression.
5. **Badges + practice.** LnL badge + `HUNTER_WEAVE_STEPS` + Explosive ranks are wired
   (journal row 125); W2 lane built RF 2x / ISS tint / OOM badge + prepull checklist
   (journal row 118). Confirm each badge appears; trap/ISS/Readiness display = badges, not
   guide arms (`hunter_open.md` §1: Readiness → RF-bar "2x window" badge; ISS 53220 →
   proc badge/tint via compat probe, engine never branches on it).
   Practice: `hunter_forced_move` drill (windows fixed cadence; grade cast legality only —
   movement itself is in-client, `buildout_practice_2026-10-17.md` §8 UNCONFIRMED).
   Post-fight HST report: confirm it opens and numbers look sane. The hunter's own
   **focused drill list** (shot priority, the clip, cooldown pops, the opener) and the
   hunter **rotation scenario** are covered in §7.
6. **Ranged bar.** Auto-shot cycle syncs the ranged bar; Raptor queue → yellow tint; cast bar
   shows the "Auto Shot" window label in the last ~0.5 s + latency (`TESTING.md`).

## 5. Druid (Era/SoD + TBC)

Sources: `bench/druid_rotation_audit_2026-10-19.md` (§§1–3, §7 hidden techniques),
`bench/verify_bank.md` §§D1–D7 (D1 BLOCKED, D4 → EMA), `bench/ids_research_2026-10-19.md` §U14.

Setup: enable druid guide. HUD D-T1 "Bleed Core" (mangle, rip, rake, shred) then D-T2
"Full Feral + Pops" (TF/Berserk auto-hide without spell data; `hud_templates.md` §4).

1. **Era runeless — expect 5CP BITE (sim-divergent by record).** E1 routes 5CP→Bite, never
   Rip (audit §Era E-2 CONFLICT HIGH: sim Rips with 8 s/5CP + 10 s gates, never Bites).
   Record every 5CP Bite prompt on Era as sim-divergent-per-header (header marks the Era
   chain doc-derived, not sim-derived) — do not "correct" in-client. No powershift prompt
   ever (E-3 GAP HIGH by design: no honest Furor/Wolfshead probe; gather writes
   `can_powershift=nil`). No Clearcast→Shred rule on Era (E-4) — OBSERVE-and-report Omen
   procs. TTD sampler feeds but ERA ignores it (E-6) — record short-fight behavior.
   Tick model 2.0 s / 20 energy / window 19–22 both sides (E-8 MATCH).
2. **SoD — TF/SR/Omen spine.** TF at ≤40 (KotJ +60 headroom; audit S-1/S-2 MATCH),
   SR ≥1CP expired→HOLD (S-3 MATCH), Omen→Shred (S-5 MATCH). Clip-Roar early-clip,
   shred-trick windows, WildStrikes pooling: GAPs, no guide expression —
   OBSERVE-and-report. S6/S7/S8 are sim-CONFLICTS (5CP Rip may clip a healthy Rip for the
   snapshot; Rake prompted where the live sim path has no Rake branch; capped-CP Bite is
   header-flagged UNCONFIRMED) — record each occurrence with stacks/durations, no verdict.
   SR durations 14/19/24/29/34 by CP (S-11 partial MATCH; lower CP unmodelled — record).
   FF pull-only manual (S-12) — record, not a failure.
3. **TBC — threshold + trick gaps.** 4CP Rip expiry-only (T-1 partial MATCH; sim RipCP is
   user-config — `guide_rip_min_cp` widget now exists, default 4 per options-ripcp lane;
   confirm the widget + default). Mangle 40 / Shred 42 + live-cost probe (T-6 MATCH).
   "Rake never on TBC" vs sim RakeTrick (T-2 CONFLICT) — record Rake windows the guide
   skips. Bite-trick/ripweave/MangleTrick absent (T-3/T-4/T-5 GAPs) — OBSERVE-and-report.
   Short-lived line: ours 12 s vs sim 10 s (T-8 CONFLICT LOW) — record 10–12 s TTD behavior.
   Powershift REMOVED by design (T-7 HIGH; sim checks Wolfshead **8345**). The **probe now
   exists** — `inputs.wolfshead_equipped` is a tri-state read (`true` worn / `false`
   readable-and-absent / `nil` unknown) refreshed at most once per second — but **no rule
   consumes it yet** (the Furor half of the powershift basis is still unproven), so
   equipping 8345 changes nothing in the guide: expect nothing, and record that. The read
   itself is **UNCONFIRMED in-client** (see the new §9 rows): with 8345 equipped, record
   whether the probe answers at all (it must not be silently `false`).
   No FF rule (T-10) — manual stance.
4. **TF/Berserk + bars.** TF/Berserk HUD slots show + glow while ready in combat; runeless Era
   Mangle hides and the row reflows closed (no gap); re-enable/revive closes the gap without
   a settings change; mid-combat hide/show flip defers reflow until combat exits
   (`TESTING.md` WotLK pass). Mangle/Rip/Rake bars count down with 4 s-final glow; Maul queue
   tint; cat/bear/travel form colours; energy tick column in cat.
5. **Practice.** `druid_powershift` drill (fixed 40-refund sim constant — D1 probe stays
   BLOCKED; sim renders honestly; `buildout_practice_2026-10-17.md` §8). Grade by energy
   at shift (20-energy rule bands S≤20/A≤30/B≤40/C≤60/D≤80/F). The druid's own **focused
   drill list** (the cat priority, the shift rule re-sourced, the Roar upkeep, the execute)
   and the druid **rotation scenario** are covered in §7.
6. **The bear chain's queued Maul — a HOLD, not a button.** In **bear form with a Maul
   queued**, run the druid rotation scenario (mode = `scenario`, §7.2) and reach the
   queued-Maul step. The panel must show the **hold** with the guide's own reason
   (`RIDE`), and the action strip must offer **no "ride" button** at all.
   - **Press nothing** → the step reads **HOLD OK**: correct, and it records **no
     attempt** — no points, no streak, no mastery tick, and the run's mis-pick count
     unchanged. **Losing points for idling is a defect** (the engine's hold contract
     forbids farming a hold).
   - **Press any action** → the step reads **ILLEGAL CAST** and grades F.
   - The druid's priority drill (`druid_finisher_order`) must grade **nothing** on a
     hold step and bank **no mis-pick** for it.
   - The druid's other nine guide holds (Tiger's Fury, Berserk, Savage Roar, Faerie
     Fire, Shifting Power, Leader of the Pack, Innervate, Elune's Light, Cat Form) name
     a spell to **press** — those must still grade as that spell, and must NOT read as a
     hold.
   - Sources: `bench/druid_hold_ride_2026-10-20.md` §§1–3 (the defect, the fix and the
     pins). **Verified offline, UNCONFIRMED in-client.**

## 6. Rogue (Era + TBC; Wrath/Forever rows noted, not tested)

Sources: `bench/rogue_rotation_audit_2026-10-19.md` (§§0–3 + §7 ranked gaps),
`bench/open_rules_2026-10-19.md` §1 (H6 BUILD shape), `bench/ids_research_2026-10-19.md` §U10,
central journal rows 112/141 (H6 wait-HOLD + SoD Envenom wiring), `bench/verify_bank.md` §H-row
notes (SS window feel), `bench/rogue_client_isolation_2026-10-19.md` (16 UNCONFIRMED).

Setup: enable rogue guide. HUD R-T1 "UxkIny-style Core" (snd, rupture, ea, tea, kick visible;
kidney/restealth/bandage provider-hide unless their toggle reads exactly true;
`hud_templates.md` §6 + `perclass_hud_guide_verify_2026-10-19.md` §1).

1. **SnD — expect the upkeep prompt (the row is ARMED).** The build ships an armed Slice and Dice
   upkeep: the guide slot `snd` (`classes/rogue.lua:868-881` — the `snd` key at `:877`), the
   practice-rotation row (`classes/rogue.lua:2415-2422`) and the engine's verdict
   (`rogue_guide.lua:1118-1156`). **The absence of a prompt is NOT the expected state.**
   The contract to observe:
   - the prompt appears when the buff is **down** (the buff read is missing — the upkeep gap) or
     when the remaining time is **inside the family's refresh window**, **and** the combo points
     are at or above the **family minimum** (`rogue_guide.lua:480-495`):
     **Era 1 CP / 3 s**, **TBC 2 CP / 0 s** (TBC re-casts only when the buff is missing — its
     10 s minimum excludes 1 CP), **SoD 4 CP / 1 s**, **Wrath 1 CP / 1 s**, **Forever 1 CP / 0 s**;
   - a **MISSING prompt while the buff is down** (at or above the family's CP minimum) **is the
     defect**;
   - a prompt **below** the family's CP minimum, a prompt from a client whose Slice and Dice
     spell does not resolve, or a prompt off a **non-numeric** buff clock is a defect in the other
     direction (an unknown clock hides — it must never answer a guess).
   Record: the timing of the prompt relative to the buff going down, the CP you were at when it
   fired, and the CP threshold you observed on your client. The `rogue_snd_upkeep` drill
   ("The debuff upkeep") grades the same window — run it (§7.3).
   **Verified offline against the tree 2026-10-20, UNCONFIRMED in-client.**
2. **Builder — the family-gated chain.** The single `builder` slot resolves the first candidate
   the client knows, in the order **`{Saber Slash, Mutilate, Hemorrhage}`**
   (`classes/rogue.lua:247-265`), with **Hemorrhage** family-gated to
   **Era / TBC / Forever** and excluded on the SoD client (the SoD client builds with a rune)
   (`rogue_guide.lua:630-666`). So:
   - on **TBC** the builder resolves **Hemorrhage** (not "Sinister Strike");
   - on **Era** it resolves **Hemorrhage** when the client knows it; with a **dagger mainhand**
     and none of the three known it resolves **Backstab**; otherwise the fallback is
     **Sinister Strike** (`classes/rogue.lua:612-631,181`);
   - on **SoD** the rune candidates (Saber Slash / Mutilate) lead and Hemorrhage is out.
   Every name resolves through the client's **own** spell data, so a name the client does not
   know falls through to the next candidate — never a wrong builder.
   Record which builder icon your client shows, and confirm it is the family's expected one.
   **Verified offline against the tree 2026-10-20, UNCONFIRMED in-client.**
3. **Era finisher — expect RUPTURE-first (sim-divergent by record).** Rule 5 routes 5CP +
   healthy TTD through `finisher_for_ttd` → "rupture" where the Era combat sim plays
   Evisc-only (E-C1 CONFLICT HIGH; sim Evisc **31016** at 5CP when SnD-active or energy≥79
   or fight<6 s). Record every Era Rupture prompt with TTD/CP. Sweaty gate: ours 0.1–0.2 s
   post-MH sword-only (Era-only) vs sim 0.5 s + energy≥79 override, no weapon check
   (E-G1 GAP MEDIUM) — test queue timing at ±0.5 s, record band feel + any ≥79 override
   behavior (override NOT shipped — record absence). Tea default 40 vs sim 29 (E-G3 GAP LOW) —
   record Tea timing. EA 3 s matches the Era IEA sim (E-G4 MATCH) — confirm EA cue at ≤3 s.
4. **TBC — pool + EA + dump deltas.** Pool bands 65/85 vs sim single line 71 (T-M1 GAP MEDIUM) —
   record 65–71 energy builder behavior. Rupture>Evisc ordering MATCHES (T-M2) but our
   any-CP ≤8 s dump vs sim 5CP ≤5 s (T-C1 CONFLICT MEDIUM) — record 1–4CP dumps on 6–8 s
   targets. EA windows 6 s-imminent + 15 s-minimum (T-G2 GAP MEDIUM) vs our flat 3 s —
   record EA timing vs the 6 s/15 s lines. Rupture refresh 4 s vs sim recast-when-missing
   (T-G3 GAP LOW) — record early refreshes. Shiv unconditional vs sim Mutilate-unknown +
   EA-context (T-G4 GAP LOW) — record Shiv prompts outside EA windows. Envenom dying-only
   MATCHES (T-M3: sim never casts 32645 mid-fight) — confirm no mid-fight Envenom on TBC.
   H6 (ea_duty ON only; default off = inert): TBC wait-HOLD at 5CP + EA below-minimum-not-imminent
   + energy below pool line, releasing to "expose" (open_rules §1 BUILD; wired per journal
   row 141) — test with `rogue_ea_duty=true`, record HOLD vs prompt; with duty off expect
   zero behavior change.
5. **SoD (same Era client) — expect DIVERGENCE, record it.** Envenom-primary + no-Rupture sim
   (S-C1 CONFLICT HIGH: Envenom rune **399963** from 4CP, Poisoned Knife **425012**,
   Vanish 1856→Envenom sequence, CttC rune) vs our ERA dying_only + Rupture-first —
   SoD Envenom rule wired per journal row 141; record whether Envenom prompts from 4CP+stacks
   and whether Rupture still prompts on SoD. 4CP lines (S-G1) + Poisoned Knife/Vanish/CttC
   (S-G2) unmodeled — record absences.
6. **Tick + probes.** Energy-tick spark tracks the 2 s tick; pooling tint follows 65/85 bands;
   Combat Potency grants never re-anchor (ambiguous tick hides — record dark-spark stretches,
   esp. under AR). Thistle Tea count probe, Vanish/Overkill window, poison-charge shape:
   all UNCONFIRMED — record per client exact behavior incl. no-cue (`TESTING.md` rogue block).
   Poison reminder shows on missing enchant; charges NOT rendered (record any client that
   exposes charges).
7. **Practice.** `rogue_energy_pool` + `rogue_ss_window` drills (journal "rogue-practice" row;
   2 drills + options copy). Run both; record grades vs felt timing. The rogue's own
   **focused drill list** (finisher order, combo-point decision, debuff upkeep, the opener)
   and the rogue **rotation scenario** are covered in §7.

## 7. Practice — rotation scenarios, drills and progression (all six classes)

Sources: `bench/practice_scenario_engine_2026-10-19.md` (the shared engine, the mode
select, the supersession map), `bench/class_features_drills_2026-10-19.md` §2 (the
per-class drill inventories), `bench/superseded_wrappers_2026-10-19.md` (the class
sessions run their own drill), `bench/practice_gamification_design_2026-10-19.md` §§2-4
(the progression model), `bench/buildout_practice_gamification_foundation_2026-10-19.md`,
`bench/buildout_practice_gamification_hook_2026-10-19.md`,
`bench/buildout_practice_progress_ui_2026-10-19.md`,
`bench/buildout_gamification_visibility_2026-10-19.md`,
`bench/buildout_options_pass_2026-10-19.md` (the badge toggle),
`bench/practice_ui_fixes_2026-10-20.md` (the shared practice-UI fixes F2/F4/F5/F7/F9/F10),
`bench/paladin_scenario_surface_2026-10-20.md` (the paladin's own scenario surface),
`bench/shared_engine_bs8_2026-10-20.md` + `bench/class_hold_statements_2026-10-20.md`
(the hold contract), `bench/rotation_gap_vs_apl_2026-10-20.md` §0.0 and §9 (the APL
utility layer and the corrected ids), and the per-class APL build/live artifacts named in
§7.2.

Setup: `/st` → the top-level **Practice** page (the practice-mode select) and the
**Progress** page. The class panels carry the same Start/Stop toggle; all three ways
(`/st practice`, the class panel, the top-level toggle) drive **one** session and a
session starts only out of combat.

1. **The practice-mode select.** On a fresh profile it must read "Class session
   (default)". Switch it to "Rotation scenario", then to "Drill list", then back; an
   unset or unknown value must fall back to the class session — never to another
   class's drill. The note under the select must read "This class ships a rotation
   scenario: yes. Focused drills: **N**." — **paladin 3, warrior 6, hunter 4, rogue 4,
   druid 4, shaman 4** (the paladin's list *also* leads with the twist timing drill,
   which the count does not include). **Record the exact text per class.**
2. **Rotation scenario, one per class** (all six, if you have the characters):
   - set Practice mode = **Rotation scenario**, start the session, and cast what the
     panel asks for (the panel's own action buttons or the class's icon grid).
   - the run is **ten decisions**; the step window is **3 s** and an expired step closes
     as a **miss**.
   - a correct cast grades **S**; a wrong or out-of-order cast grades **F**; a step the
     class cannot decide (the panel shows no expected action) must record **no attempt**
     at all — if you see a grade there, that is a defect: record it verbatim.
   - **A hold is a decision, unknown is not.** When the class's own engine holds (the
     rogue's **POOL**, the shaman's **RIDE**/**WAIT**, the hunter's **RIDE**/**HOLD**, the
     paladin's **RIDE** / "nothing is ready", the warrior's **RIDE**/**HOLD**), the
     prompt must show the hold and the class's own reason. Casting during the hold
     must read **ILLEGAL CAST** and grade F; doing nothing must read **HOLD OK** and
     record **no attempt** (no points, no streak). The **druid states one press-nothing
     hold** — the bear chain's queued **Maul**, whose guide verdict is `RIDE` — so it
     must read as a **hold**, never as a press; the druid's other nine guide holds name
     a spell to press and stay actions. The warrior's **CANCEL** cue names the Execute,
     so it is an **action**, not a hold.
   - **The utility rows are in the strip.** The scenario carries the class's **full** sim
     priority list, so the action strip must show the utility rows too. Per family:
     - **warrior** — Battle Stance, Berserker Stance, Bloodrage, Battle Shout,
       Recklessness, Death Wish (Sweeping Strikes on TBC/Forever; Thunder Clap /
       Shattering Throw / Heroic Throw on WotLK). **Gladiator Stance must never appear**
       (its gate is the T1 set bonus — see P9-1).
     - **hunter** — Rapid Fire, the Serpent Sting upkeep, the aspects (Viper / Hawk /
       Dragonhawk / Falcon), Kill Shot (the SoD rune / the WotLK rank), Silencing Shot,
       Explosive Trap, Multi-Shot, Black Arrow, and the Forever melee rows (Raptor
       Strike, Hunter's Mark, Mongoose Bite, Immolation Trap, Wing Clip, Arcane Shot).
       The **Forever client has no Steady Shot** — no Steady row on that client.
     - **rogue** — Vanish (SoD / WotLK / Forever), the SoD Poisoned Knife, Tricks of the
       Trade and Killing Spree (WotLK), and the Forever cluster: Preparation,
       Premeditation, Blood Fury, Elune's Light and the Gnome racial **Eureka!**.
       **Cloak of Shadows does not exist on the TBC or Forever clients** — if you see a
       Cloak row, that is a defect.
     - **druid** — Cat Form, Leader of the Pack, Faerie Fire (Feral), Innervate, Elune's
       Light. The **Bloodlust row must never appear** (2825 is the Shaman's spell — see
       P9-5) and **Claw stays RESERVED** (no read).
     - **shaman** — Strength of Earth, Mana Spring (TBC), Frost Shock (TBC), Bloodlust
       (WotLK), and the Lightning Shield maintain (SoD/Forever).
     - **paladin** — the utility layer **landed**: the paladin's rotation table carries
       **17 rows** (`classes/paladin.lua:4425-4571,4586-4602`), family-gated, and the strip
       shows the rows the running family **and** the running build's order carry. Per family:
       **Era** — Judgement, twist, Seal of Command, Hammer of Wrath (4);
       **TBC** — Crusader Strike, Judgement, twist, Seal of Command, Seal of Blood,
       Consecration, Exorcism (7 — no Hammer of Wrath: the execute arm is Era/Forever only);
       **Forever** — Judgement, twist, Seal of Command, Consecration, Exorcism, Hammer of
       Wrath (6); **Wrath** — Hand of Reckoning, Hammer of Wrath (48806), Crusader Strike,
       Judgement, Divine Storm, Consecration, Exorcism, Holy Wrath (8);
       **SoD** — the build's own FCFS order (`nextaction.lua:983-998`), e.g. Exodin
       `exo > cs > ds > judge > cons > how` (6) or Shockadin `exo > am > hs > cs` (4).
       **Three of the seventeen rows have no engine arm** — Judgement of Wisdom (53408),
       Holy Strike (10333) and Divine Favor (20216) — so they are citations only and never
       enter the panel's button vocabulary (`classes/paladin.lua:4544-4571,4854-4864`); a
       pressable button for one of them is a defect. **Record every row you see**, and check
       that a row the family does not carry never shows.
   - **A family that does not carry a row must never show it** — the strip is
     family-gated. Record per class which utility rows appeared and which did not.
   - **The strip must not grow.** Across the ten steps the action/drill row must show one
     set of buttons, reused — not a growing pile (the row used to rebuild its buttons
     every step and only hide the old ones).
   - record per class: how many of the ten steps were gradeable, the run's grade, and any
     step whose expected action looked wrong to you. OBSERVE-and-report the rotation
     itself — do not "fix" it in-client.
3. **Focused drills, one list per class.** Set Practice mode = **Drill list**; one
   button per drill. Run every drill of every class you have a character for. The sets
   this build ships:
   - **paladin** — **Twist timing** (the twist drill **leads** the paladin's list; its
     press hands the panel over to the twist session), FCFS priority order, Prepull seal,
     Judgement fit
   - **warrior** — The core rotation, The core window, The debuff upkeep, The execute
     burn, **The queue window** (the HS/Cleave queue drill — §7.10), **The opener**
     (the pre-pull drill — §7.9)
   - **hunter** — Shot priority, The clip, Cooldown pops, The opener
   - **rogue** — The finisher order, The combo-point decision, The debuff upkeep, The opener
   - **druid** — The cat priority, The shift rule re-sourced, The Roar upkeep, The execute
     (the panel prints the label "The shift rule, re-sourced" — comma included)
   - **shaman** — The enhancement priority, The stack decision, The Stormstrike decision,
     The totem upkeep
   Record each drill's grade. A drill that cannot judge must read **UNKNOWN** and score
   nothing — never a guess.
   - **The pick channel.** A drill that needs your choice (the priority-order drills)
     grades the **action you pressed**: press one of the class's action buttons first,
     then the drill button. A drill press that answers UNKNOWN after a correct action
     press is a **defect** — this used to happen on every press for five of the six
     classes, because the row built the context with no pick.
   - **The class session routing.** The **class session** (the default mode) must start
     the class's **own** drill and grade through it — the shaman and the druid included,
     whose sessions used to be unreachable and whose panel icons were silent no-ops. A
     drill cast with **no session at all** must print a refusal, never do nothing quietly.
   - **The twist drill belongs to the paladin.** A class that publishes no drills of its
     own and owns no twist drill must be refused loudly ("No practice for this class.")
     rather than inherit the paladin's minigame.
4. **The level badge + session XP bar.** On a fresh profile the badge is drawn under the
   practice panel: the level ("Lv 1"), the XP into the level, the level bar and the
   session XP. After a graded attempt the XP must move. The **Progress** page carries the
   badge toggle: turn it off and confirm the badge disappears and no chat notice fires,
   then turn it back on. A saved `false` must survive a `/reload` (the badge stays off).
5. **The Progress page.** Level + renown line, the XP bar, the per-drill mastery table
   (tier, mastery %, attempts, accuracy — a drill under 20 attempts must read
   **Unranked**), the achievements list (locked and unlocked), the stats summary (runs,
   attempts, accuracy, rolling-20, last session, time active, best score, best grade,
   best streak) and the all-classes line. The page writes no settings key of its own.
6. **The stats frame** (the Progress page's "open stats" button): the accuracy
   **sparkline** over the last 50 sessions, the per-drill table, the per-class table and
   the session history (newest first, wheel scrolled — scroll it and record whether the
   list moves and whether the thumb tracks). The Scope button cycles the classes that
   have data and the account scope. The frame must be hidden again when it is closed.
7. **The reset** (the Progress page): press it once — it must ask; press it again — the
   progress must be gone (level back to 1, the tables empty). Then run one graded
   attempt and confirm the badge reads "Lv 1" again.
8. **The design elements.** `/st design` must list **13** targets: 3 swing bars, seal
   icons, Successful twist text, Cooldown HUD, Rotation label, Next action guide,
   Practice panel + rotation display + timeline, Hunter shot report, Warrior Execute
   report. Drag each and confirm it drops where dragged; the two report targets appear
   only while their report frame is shown. The practice **level badge is not one of the
   13** — it hangs under the panel and is not draggable (record it if it moves).
   **The count is class-dependent: a druid registers a 14th** — the **Combo Points** pips
   row (`classes/druid.lua:1506-1522` → `bars.lua:1168-1195`). Expect **13 on every other
   class** and **14 on the druid**, and record the count you actually saw.
9. **The pre-pull phase.** The sims' **pre-pull** rows live in their own per-class table —
   they are never part of the combat rotation. The **hunter's**, the **rogue's** and the
   **warrior's** tables have a drill that grades the opening sequence
   (`hunter_prepull`, `rogue_opener`, `warrior_prepull`); the **paladin's** table also has
   a drill (`paladin_prepull`, "Prepull seal") — it grades the **seal and its lead**, not
   the utility rows, so the paladin's utility pre-pulls stay citations only. The
   **druid's** and the **shaman's** tables are carried as citations only — no drill grades
   them, so there is nothing to run for those two beyond checking that no pre-pull row ever
   shows up in the combat rotation. Run the drills that ship and record the order and the
   offsets each class asks for:
   - **warrior** — per family: Berserker Stance @-1 and Bloodrage @-5 (SoD); Berserker
     Rage @-4.5, Bloodrage @-3, Battle Shout @-3, Charge @-0.9, Intercept @-0.9 (TBC);
     the Forever list adds Battle Stance @-4 (arms) and uses Intercept 20617; WotLK runs
     Berserker Stance @-20 (fury), Bloodrage @-10, Berserker Rage @-5 (fury),
     Recklessness @-3, Battle Stance @-2 (arms), Death Wish @-1.5 (fury).
   - **hunter** — **the table has no Era list at all**: `ST.HUNTER.PRACTICE_PREPULLS`
     carries **TBC, SoD and Forever only** (`classes/hunter.lua:3419-3462`), so on **Era the
     opener drill answers UNKNOWN** — that is the correct answer, **not** a defect
     (`classes/hunter.lua:4406-4409`). The rows that do exist are: **SoD** — Aspect of the
     Falcon @-5, Aimed Shot @-3.5, Blood Fury @-1.95, Rapid Fire @-0.45, Serpent Sting
     @-0.45; **TBC** — Aspect of the Hawk @-20, Steady Shot @+0.5; **Forever** — Hunter's
     Mark @-22, Aspect of the Hawk @-20.
   - **rogue** — Blood Fury @-1.5 (SoD), Adrenaline Rush @-1 (Era/TBC), the Vanish buff
     @-1 (WotLK, an aura), and **Blade Flurry 13877 @-2** / Premeditation @-2 / Stealth @-1
     (Forever) (`classes/rogue.lua:2876-2915`).
   - **druid** — Faerie Fire (Feral) @-1 and Tiger's Fury @-3.5 (Era), Savage Roar @-8
     (SoD), Cat Form @-10 (TBC), Berserk @-1 (WotLK). The Forever APL has no pre-pull row.
   - **shaman** — per family: Strength of Earth @-6, Windfury Totem @-4.5, Grace of Air
     @-3, Searing Totem @-1.5 (Era); Lightning Shield @-10, Mana Spring @-8.25, Grace of
     Air @-6.75, Strength of Earth @-5, Searing Totem @-2.75, Blood Fury @-1.25 (SoD);
     Windfury @-8, Strength of Earth @-5, Mana Spring @-4, Fire Nova @-3, Grace of Air
     @-2, Drums @-1 (TBC); Grace of Air @-8, Flametongue Totem @-7, Strength of Earth
     @-6, Mana Spring @-5 (Forever); Call of the Elements @-3 (WotLK).
   - **paladin** — the table carries **11 rows** (`classes/paladin.lua:4630-4719`):
     **TBC** — Sanctity Aura 20218 @-18.5, Seal of Command 20375 @-1.5, Seal of the
     Crusader 27158 @-1.5, Judgement 20271 @0, Seal of Blood 31892 @0, Seal of Command
     20375 @0 (the two PrepullSeal / PullSeal branches); **Forever** — **Retribution Aura
     10301 @-10** (the name is **CONFIRMED**, not UNCONFIRMED), Seal of Command 20920 @-3,
     Seal of the Crusader 20308 @-1.5; **SoD** — Seal of Command 20920 @-3, Seal of
     Martyrdom 407798 @-1.5. The paladin's pre-pull **drill** grades the *seal* and its
     lead, so the utility rows above are citations only.
   The **drill's own clock** counts down to the family's first opener (the hunter's shape);
   a pre-pull row showing up in the combat rotation would be a defect.
   **The pre-pull rows above were verified against the tree on 2026-10-20.**
10. **The warrior HS/Cleave queue drill** (`warrior_hs_queue`) — the operator's mechanic.
   With an offhand weapon equipped and dual-wielding, queue a Heroic Strike or Cleave and
   grade the press:
   - the window is the gap between the **mainhand's last swing** and the **offhand's next
     swing**; the grade is the room on the **tighter** of the two sides — S ≥ 250 ms,
     A ≥ 150 ms, B ≥ 80 ms, C ≥ 20 ms, D inside the window, F outside it (too early =
     the offhand swings after the ability, too late = the offhand already took the
     penalty).
   - the mechanic behind it, with the sim's own citation: the queue lifts the dual-wield
     miss penalty (`DisableDWMissPenalty`), and the penalty it lifts is **+19 % over a 5 %
     white base**. The sim's own 250 ms is its **reaction-time model**, not a client fact:
     the in-client window is **UNCONFIRMED IN-CLIENT** and this drill is what settles it.
   - record the felt window per client, the grade you got, and whether the drill ever
     answered UNKNOWN (only a **Heroic Strike / Cleave** press is this drill's decision —
     any other press answers nil, which is by design).
11. **The logout-persistence check (run a session → LOG OUT → log in).** This is the
    check that proves a completed session survives the client quitting.
    - Run a practice session (any mode — the class session is enough), grade a few
      attempts so the run has a score, a time active and a daily streak, then
      **log out of the game and log back in**.
    - After the re-login, open the **Progress** page (options → Progress) and read off:
      - the **run counter** (the stats summary's `runs`),
      - the **time active**,
      - the **history row** (the stats frame's session history must carry the run you
        just finished), and
      - the **daily streak** (the streak line in the stats summary).
      All four must be there. Before the fix, logging out lost the completion bonus, the
      daily streak, the run counter, the accumulated time active and the history row —
      only the per-attempt XP survived, and nothing said so.
    - **Do NOT use `/reload` for this check.** A UI `/reload` fires **no**
      `PLAYER_LOGOUT` and writes **no** SavedVariables — the client serialises them at
      logout only — so a mid-session reload loses the in-flight session whatever the
      addon does. That is client behaviour, not an addon defect, and it is why the
      session's flush is a logout flush. Log out to test persistence.
    - Sources: `bench/practice_persist_2026-10-20.md` §"H2" (the defect, the flush and
      the reload caveat). **Verified offline, UNCONFIRMED in-client.**
12. **The mid-session reset check (no half-state).** Start a session, grade a few
    attempts, then press the **Progress** page's reset **while the session is still
    running** (answer the confirm), then grade another attempt.
    - The XP, the streak and the stats must be **recorded again** — before the fix the
      score kept moving while no XP, mastery, streak, stats or badge did, silently.
    - The panel badge must show only the **post-reset** XP (the erased XP must not stay
      on the "+N XP" line).
    - The session itself must keep running: the score, the simulation and the panel are
      untouched; only the progression bookkeeping restarts.
    - Source: `bench/practice_persist_2026-10-20.md` §"M1". **Verified offline,
      UNCONFIRMED in-client.**

## 8. `/st diag` paste — the verbose block (ids + errors, every client)

The diag-ids-errors lane (central journal row 135; `desks/diag/journal.md` 2026-10-19 entry)
ships print-only, capped sections in the verbose diag. **`/st diag` IS the verbose form** —
there is no `verbose` sub-command (`main.lua:2013-2046`).

- **WANTED_IDS (67 ids, DATA-only):** `diag.lua:74-96` — U1 Forever ranks/triggers
  (1310785/1310786/1293525/1293526/1293527/1293248/1312639), U3 VR/Victorious
  (34428/32216), U9 Forever bonus kit (14287/25295/14325/25296/14266/14268/1317257/469145/
  3045/5384/2643/20904/14271/20572), U10 rogue per-client set (57993/51662/26889/58426/
  57934/51690/48668/26864/26863/34413/26862/5938/32645/26867/26865/11281/1241584/16511/
  11294/6774/11275/11300/13750/7676/13877/14177/1310703/31016/425096/1856), U11 JotC
  (21183), U12 shaman (17364/440580/408490/408507/425339/408498/408505/425336), U13 warrior
  (11605/25286/20569), U14 Berserk (50334), U17 Explosive R3 (60052). Resolved via
  `st.api.GetSpellInfo` (name/icon/cast/known); unresolvable prints **UNRESOLVED** —
  never errors, never writes. Source header cites `bench/ids_research_2026-10-19.md` U1–U17.
- **The names in §9's table and in this list were corrected on 2026-10-20** — several ids
  carried the wrong name in the corpus (17364, 1857, 9850, 2825, 51662, 26867, 1241584,
  1310703, 1259812, 54758, 61006 / 60053, 34120, 61847, 25296, 12292, 18499 …). The
  **corrected** table sits with the P9 rows in §9; read it before writing a name next to an id
  in your report.
- **Error ring:** `seterrorhandler` chain (keeps + calls previous), bounded `ERROR_MAX 8`,
  in-memory only, newest-last, 200-char single-line cap (`diag.lua:527-553` — the cap at
  `:543-545`; the handler is installed at `:556-594`).
- **Caps:** `MAX_LINES 85` for the whole report with explicit +N count lines
  (`diag.lua:60,640-671`). The **login one-liner** (the first line, printed by the addon at
  login) is byte-identical to the first line of the verbose block (untouched).
- **The verbose block's shape** (`diag.lua:681-709`): the login line, then `flags`, `modules`,
  **`ticks`** and `secrets`, then the ids section, then the error-ring section — and, after the
  block, the `diag runtime …` counters line from `main.lua:1947-1998`
  (`bar_hook_errors`, `callback_errors`, `hud_cleu_register_errors`,
  `paladin_lcd_register_errors`, `rf_failures`, `rf_checker_laps`, `rf_checker_exhausted`,
  `rf_disabled_after_failures`).

Paste per client: the login one-liner + the FULL verbose block (the flags / modules / ticks /
secrets lines, the ids lines, the error-ring lines, any +N count lines) + the `diag runtime …`
line. 236-check suite + 8/8 mutations hold offline
(`desks/diag/journal.md`); only the live resolution values are unknown — that is what
this paste supplies.

## 9. ID-confirmation table — what to confirm in-game

Mark each: CONFIRMED (`GetSpellInfo` answered + behavior matches) / UNRESOLVED (diag says
so) / ABSENT-BY-DESIGN (table deliberately empty — rogue/ss note). Do not add web evidence;
web-CONFIRMED ≠ client-CONFIRMED. **Before you write a name next to an id, check the
corrected-id table below** — the corpus carried wrong names for several of them until
2026-10-20.

| # | Id(s) | What to confirm | Status going in |
|---|---|---|---|
| U1 | 1310785, 1310786 (Sniper R3/R4); 1293525/26/27 (Hawk R2–R4); triggers 1293248, 1312639 | In-game `GetSpellInfo` on **1.60.x only** (out of scope for this pass — record N/A here) + rank↔id mapping | SIM-CONFIRMED, CLIENT-UNCONFIRMED (`ids_research.md` U1). Operator Sniper/Hawk rank notes in central journal rows 144–145 are web/operator-sourced, mapping still owed |
| U2 | hawk-count source | Guardian-pet enumeration / UnitAura 1293248/1312639 / combat-log — which (if any) yields a count | No public contract found; probe owed (`hunter_open.md` §3 BLOCKER) |
| U3 | 34428 (VR), Victorious aura | Spell id on 1.60.x (34428 is WotLK-only) + aura id/duration + `IsSpellUsable` post-kill | UNCONFIRMED (`ids_research.md` U3; `open_rules.md` §3 HOLD DORMANT) |
| U4 | TBC FS fight≥12 s gate | FS behavior in the first 12 s of a TBC fight | Sim-side UNCONFIRMED (`ids_research.md` U4) |
| U5 | SoD p4-twist path | Correct `ui/paladin/apls` path (404 was wrong guess) | UNCONFIRMED (`ids_research.md` U5; p8-twist carries the 10% rule independently) |
| U6 | SoD SS 6 s trigger | Rune vs base (sim models flat 6 s) | UNCONFIRMED (`ids_research.md` U6); operator confirms 6 s CD behaviorally (journal row 148) |
| U7 | feel of every row | Sims are not the game (notably Forever 2H + custom ids) | Standing caveat |
| U8 | Bloodthirst Forever | Name-only by design | Same boat as U3 |
| U9 | 14287/25295/14325/25296/14266/14268/1317257/469145/3045/5384/2643/20904/14271/20572 | 1.60.x `GetSpellInfo` each | SIM-CONFIRMED only (U9) |
| U10 | rogue per-client set (see §8 list) | In-client `GetSpellInfo` per client; the class ships **no remembered id tables** — every spell the HUD/guide needs is resolved through the client's own spell data by exact English name at init (`classes/rogue.lua:7-9`, the no-remembered-ids rule) | SIM-CONFIRMED only (U10); never wire from this pass |
| U11 | paladin per-client (SoC procs, CS, JotC 21183, HoW/Exo/Cons ranks, sealDuration, TwistOfLight string) | JotC 21183: record the **20 s max-rank / 10 s lower-rank** durations and the melee refresh **per client**; the rest guide/sim-sourced | 21183 is **web-CONFIRMED** (wowhead / warcraft.wiki — `verify_bank.md` §2) and in-tree (`classes/paladin.lua:2508-2537,2670-2688`); the **in-client shape is UNCONFIRMED** — no observation of it in a client exists in the corpus. Rest SIM-side (U11) |
| U12 | shaman per-client (SS 17364; runes 440580/408490/408507/425339/408498/408505/425336; TBC totems; thresholds) | 17364 CONFIRMED (12 s +20%); runes SIM-sourced | 17364 CONFIRMED (`verify_bank.md` §2); 66842 is client-sourced (P8-1); rest U12 SIM-only |
| U13 | warrior per-client (OP window, Slam 11605, HS/Cleave ranks, Blood Surge/Sudden Death, floors) | OP 5.0 s; Slam 11605; HS 25286/Cleave 20569; Blood Surge aura; 412507 CONFIRMED | 412507 operator-CONFIRMED in-game; rest U13 SIM-only |
| U14 | druid per-client (TF/Berserk 50334 Wrath, SP 50 vs 60, 16 s/8 s ISPP, SR 14–34 s, Rip/Rake/Mangle costs, FF rules) | 50334 exists client-side; Wolfshead **8345** equipped-check (the probe now ships and is tri-state — P8-2) | TF name-based PARTIAL; 8345 + rest U14 |
| U15 | ISS 53220 mechanics | 12 s buff page-confirmed; +15%/−20%/consumed-on-cast SIM-side | Page confirms duration; numbers SIM-side (U15) |
| U16 | H2 lust-suppression | No APL lust branch in any fetched APL (SIM-DIVERGENT) | Orchestrator-ruled CUT (U16; journal rows 118/120) — confirm behavior, not an id |
| U17 | 60052 R3 Explosive | Page existence via cited link only | Direct snippet owed (U17) |
| OP-1 | 412507 Blood Frenzy | Operator-CONFIRMED in-game 2026-10-19 | Re-confirm present + behavior on SoD |
| OP-2 | 425339 Molten Blast; 408507 Lava Lash | warcraftdb CONFIRMED (match sim ids) | Re-confirm castability in-game |
| OP-3 | 399963 Envenom (Rune of Venom, item 210322) | wowhead page exists; latch stays frozen pending in-client `GetSpellInfo` | Still needs in-client proof — record |
| OP-4 | 2825 BL / 32182 Heroism; 21183 JotC 20 s; 17364 SS 12 s | `verify_bank.md` §2 CONFIRMED | Re-confirm durations in-game |
| OP-5 | Exhaustion 57723/57724; WF/GoA totem ids; Furor talent id; mana-regen probe; target-count sensor | All UNCONFIRMED (`verify_bank.md` §§2/7) | Record any client that answers |

### P8 rows — the wave's Still-UNCONFIRMED list (added 2026-10-20, Phase 8)

These six rows are the surfaces that landed offline but were never observed in a client.
Mark each CONFIRMED / UNRESOLVED / STILL-UNCONFIRMED with what you actually saw.

| # | Item | What to confirm | Status going in |
|---|---|---|---|
| P8-1 | **66842** (Call of the Elements) + the water-totem read (client slot 3) | On **3.80.2** (and any Wrath client): does the CoE guide slot ever appear while the water totem has under 20 s left? Is the water slot readable at all — the read is tri-state (the seconds left / `0` for an affirmatively empty slot / `nil` for an unknown read)? On Era/SoD/TBC expect **no** CoE prompt (the rule is Wrath-only) | Id + slot number are **client-sourced** (the client's own `Constants.lua`); the behaviour is **UNCONFIRMED in-client** (`bench/shaman_coe_ss_2026-10-19.md` §1-2) |
| P8-2 | The **Wolfshead** read (item 8345) | With the helm equipped: does the probe answer `true` (worn) / `false` (the read worked, not worn) / `nil` (unknown)? It must never be a silent `false`. No rule consumes it yet, so equipping it must change **no** prompt | The probe + tri-state shipped (`bench/buildout_closure_triad_2026-10-19.md` §3); the read is **UNCONFIRMED in-client** |
| P8-3 | The **Serpent Sting** target read | Per client: is the target debuff readable at all, and does the guide ever withhold the Chimera while the sting is actually **UP**? A false "down" is a defect, not a client quirk | The read shipped (`bench/hunter_serpent_2026-10-19.md`); **UNCONFIRMED in-client** |
| P8-4 | The three **Forever ids**: 1311703 (Echo of Command), 1311704 (Echo of Righteousness), 10333 (Holy Strike) | On 1.60.x: do the three names resolve? A wrong or absent answer must leave the input **unknown** — never a wrong prompt | Web-confirmed, **client-unconfirmed**, name-anchored (`bench/buildout_paladin_bs5_2026-10-19.md`). 1.60.x is out of this pass's client scope — record **N/A** here |
| P8-5 | The warrior's **Slam cast-time read on a name-only TBC client** | The Slam bar's fallback reads the rank's cast time through the **id** form. On a TBC client that answers names only, that read finds nothing, so the fallback stays at the reference's **1.5 s** even when the rank resolved. Confirm what the "SLAM X.Xs" bar actually shows on TBC — the real cast time, or 1.5 s — and record it | **UNCONFIRMED in-client**; a filed, unfixed gap (`bench/resolver_callers_2026-10-19.md`, "A pre-existing gap this lane did NOT touch"). Do not "fix" it in-client, just record |
| P8-6 | The warrior **HS / Cleave queue drill** (`warrior_hs_queue`) | **SHIPPED — the earlier "NOT SHIPPED" note on this row was wrong.** The drill landed on 2026-10-20 and the warrior's drill set is now **six** (§7.3). Run it: §7.10 has the window, the bands and the mechanic's citation. Record the felt window per client — it is UNCONFIRMED IN-CLIENT by design (the sim's 250 ms is its own reaction-time model, not a client fact) — and still record the queue-tint behaviour (colour on queue, clearing, the insufficient-rage colour) | The drill + the pure band helper shipped (`bench/warrior_hs_queue_2026-10-20.md` §§1-2); the window is **UNCONFIRMED in-client** |

### The corpus was corrected — do not trust the old ids

The rotation-gap analysis (`bench/rotation_gap_vs_apl_2026-10-20.md`) is the **seed** of most
of the wrong ids in the bench corpus. The five utility-layer lanes re-fetched every APL file and
every sim spell table on 2026-10-20 and **disproved 31 ids, names and gates**; the corrections
are applied in place in that file (§0.0 lists each one with its old value, its corrected value
and its evidence; §9 summarises them) and sixteen other bench files were corrected the same way.
**If you are reading an older bench file's name for an id, assume it is wrong until you check
§0.0.** The headline corrections that matter for this pass:

| id | the old name in the corpus | the corrected name | note |
|---|---|---|---|
| 17364 | Nature's Wrath (shaman) | **Stormstrike** | no wowsims shaman sim has a Nature's Wrath ability at all |
| 29228 | Flametongue Weapon (shaman) | **Flame Shock r6** | the Flametongue Totem is 16387 (r4) and it is a pre-pull row |
| 49231 | Lightning Shock (shaman, WotLK) | **Earth Shock** | 49233 = Flame Shock, 49236 = Frost Shock |
| 10497 | Rockbiter Weapon (shaman) | **Mana Spring Totem r4** | neither the SoD nor the Forever pre-pull carries a Rockbiter row |
| 1857 | Cloak of Shadows (rogue) | **Vanish rank 2** | the spell does not exist on the TBC or Forever clients (removed in 2.3) |
| 14183 | Shadowstep (rogue, Forever) | **Premeditation** | |
| 1241584 | Shadowstep rank (rogue, Forever) | **Mutilate rank 4** | |
| 26867 | Deadly Poison (rogue, TBC) | **Rupture** | the TBC APL casts no Deadly Poison at all |
| 51662 | Mutilate (rogue, WotLK) | **Hunger for Blood** | the APL's mutilate row casts 48666 |
| 1310703 | the Forever Expose (rogue) | **Venom** | |
| 1259812 | Gnome Eureka (rogue, Forever) | **Eureka!** (the Gnome racial) | 1259799 = "Elune's Light" |
| 54758 | Hypersharp Weapon (rogue, WotLK) | **Hyperspeed Acceleration** | "Hypersharp Weapon" does not exist in the WotLK client at all |
| 9850 | Mangle (druid, TBC/Forever) | **Claw rank 5** | the **Forever client has no Mangle spell at all** |
| 13494 | Faerie Fire (Feral) (druid, Era) | **"Haste"** on the 1.15 client | the client's Leader of the Pack is **17007**; the Era APL has **no Rip row** |
| 2825 | the druid's Bloodlust | the **Shaman's** Bloodlust | the TBC druid sim has no Bloodlust — the APL row is dead for a druid |
| 61006 / 60053 | Kill Shot 53351 / Explosive 53301 (hunter, WotLK) | the APL casts **61006 / 60053** | 53351 / 53301 are the client's rank-1 fallbacks |
| 34120 | Steady Shot 56641 (hunter, TBC) | the TBC APL casts **34120 r1** | 56641 does not exist on the TBC client |
| — | the Forever Steady Shot row | **removed** | the **Forever client has no Steady Shot at all** (it arrived in 2.3) |
| 61847 | Aspect of the Wild (hunter) | **Aspect of the Dragonhawk** | the WotLK client renamed it |
| 25296 | Aspect of the Cheetah (hunter) | **Aspect of the Hawk** | the Cheetah is 5118 |
| 12292 | Sweeping Strikes on TBC | **Death Wish on TBC**, Sweeping Strikes on Forever | both APLs cast 12723 |
| 18499 | Improved Hamstring (warrior) | **Berserker Rage** | 25212 is the TBC Hamstring |

### P9 rows — the APL utility layer's still-UNCONFIRMED list (added 2026-10-20)

Seven items the utility-layer wave left open. Each one is either a row that must **never**
prompt or a read that has no client source yet. Mark each CONFIRMED / UNRESOLVED /
STILL-UNCONFIRMED with what you actually saw.

| # | Item | What to confirm | Status going in |
|---|---|---|---|
| P9-1 | **Gladiator Stance** (SoD, 412513) — the T1-set gate | The row must **never** prompt: the SoD APL gates it on the T1 damage **set bonus** (`auraIsKnown` on 457817 / 464241), and the client's aura list reports the **active** auras only, so it can answer the Forecast buff but not the set ownership. Confirm the guide never asks for the stance on SoD, and record whether the Forecast aura (457817) is readable at all while the buff is up | `engine = false` — the read exists, the arm does not (`bench/warrior_apl_utility_live_2026-10-20.md` §4; `bench/warrior_utility_residuals_2026-10-20.md` §1). The missing read is the **six item ids** of the "S03 - Item - T1 - Warrior - Damage" set |
| P9-2 | **Chain Lightning** (shaman) — the unreadable enemy count | The row must **never** prompt: the APL's `numberTargets >= 2` has no client counterpart, the clients' FrameXML carries **no** Chain Lightning code at all (0 hits in every branch), and the gather feeds `target_count = nil`. Confirm the guide never asks for Chain Lightning and record what it asks for instead | `live = false, engine = false`; rule 13 stays in the engine as the filed skeleton (`bench/shaman_residuals_2026-10-20.md` §1.3) |
| P9-3 | **Hypersharp** (WotLK rogue, 54758) — a spell that does not exist | "Hypersharp Weapon" has **zero hits** across the WotLK client's spell, enchant and item tables; 54758 is the belt enchant's *effect* ("Hyperspeed Acceleration", a 60 s cooldown that applies a 12 s haste aura). The row is honestly off and its dead arm was removed: confirm the guide never prompts it and that the rotation label never names it | `live = false, engine = false`; the dead arm and its rule slot 5e were removed (`bench/rogue_apl_residual_reads_2026-10-20.md` §2.2) |
| P9-4 | The druid's **cat-vs-bear spec read** | The Cat Form arm is armed by a Feral-tree spec probe (Era/SoD 17392, TBC 27011, Forever 17007), the Cat Form aura (768) and the form index. The clients this addon targets expose **no** cat-vs-bear spec read (the talent trees are readable on WotLK only), so a **Feral-tree bear tank** out of the bear form can still be told to shift. If you are a bear on Era/TBC/Forever, watch for a spurious CAT FORM call and record it | The arm shipped with the limit stated in the row's own `gate` text (`bench/druid_apl_residuals_2026-10-20.md` §3) |
| P9-5 | The druid's **Bloodlust row** (TBC, 2825) — a dead variable | The row must **never** prompt: 2825 is the **Shaman's** Bloodlust (the TBC druid sim has no Bloodlust at all, so the APL's row is dead for a druid), and the APL's own "Bloodlust Time" variable (5 s in the shipped APL) has no addon counterpart. Confirm the druid guide never asks for Bloodlust | `live = false, engine = false` (`bench/druid_apl_residuals_2026-10-20.md` §4) |
| P9-6 | The shaman's **Frost Shock pick** (TBC) | The APL's Shocks group picks **one** filler; the option `guide_filler_shock` (earth / frost, default `earth`) states the choice. With Frost Shock picked the Frost Shock row must prompt and the Earth Shock filler must go quiet; with the default the Earth Shock filler answers. Record both | The option + the class-owned read shipped (`bench/shaman_residuals_2026-10-20.md` §1.2); the pick is **UNCONFIRMED in-client** |
| P9-7 | The shaman's **TBC twist ranks** | The shipped row keeps **8512** (the Windfury Totem rank-1 id, a deliberate downrank) and carries the APL's own TBC id **25587**; the alternation's other half is the Grace of Air Totem **25359 r3**. Record which rank the twist icon shows on TBC | The rank choice is the operator's open decision (O-1); the row ships both ids with the reason (`bench/shaman_residuals_2026-10-20.md` §1.4) |

### P10 rows — the audit-fix wave's still-UNCONFIRMED list (added 2026-10-20)

Four items the six audit fixes landed offline and were never observed in a client. Each is
either a surface that must behave a specific way or a read that has no client source yet.
Mark each CONFIRMED / UNRESOLVED / STILL-UNCONFIRMED with what you actually saw.

| # | Item | What to confirm | Status going in |
|---|---|---|---|
| P10-1 | The druid's **press-nothing hold** (the bear chain's queued Maul) | In **bear form with a Maul queued** the scenario must show the **hold** (the guide's `RIDE`) and offer **no "ride" button**. **Press nothing** → HOLD OK, correct, **no attempt** (no points, no streak, no mastery tick; the run's mis-pick count unchanged). **Press anything** → ILLEGAL CAST, grade F. The priority drill must grade nothing on a hold and bank no mis-pick. The druid's other nine guide holds (Tiger's Fury, Berserk, Savage Roar, Faerie Fire, Shifting Power, Leader of the Pack, Innervate, Elune's Light, Cat Form) must still grade as that **spell**. Run it: §5.6 | The split landed (`ST.DRUID.PRACTICE_HOLD_KEYS` / `ST.DRUID.PRACTICE_HOLD_PRESSES_NOTHING`; `bench/druid_hold_ride_2026-10-20.md` §§2–3); **UNCONFIRMED in-client** |
| P10-2 | The **session flush at logout** | Run a session, grade a few attempts, **log out**, log back in. The Progress page must show the **run counter**, the **time active**, the **history row** and the **daily streak**. All four must be there. **Do not test this with `/reload`** — a reload fires no `PLAYER_LOGOUT` and writes no SavedVariables, so it loses the session whatever the addon does (client behaviour, not a defect). Run it: §7.11 | The flush landed (`ui.flush_progress_session`, three callers: the session stop, `PLAYER_LOGOUT`, the panel's hide; `bench/practice_persist_2026-10-20.md` §"H2"); **UNCONFIRMED in-client** |
| P10-3 | The **mid-session Progress reset** | Reset the Progress page while a session is running (answer the confirm), then grade another attempt. The XP, the streak and the stats must be **recorded again** (before the fix the score moved while no XP, mastery, streak, stats or badge did, silently). The badge must show only the **post-reset** XP. The session keeps running. Run it: §7.12 | The two-half fix landed (the attempt recorder ensures the profile; the reset clears the live session's counters and repaints the badge; `bench/practice_persist_2026-10-20.md` §"M1"); **UNCONFIRMED in-client** |
| P10-4 | The paladin's **spell-book probe on a talent id** | The paladin's WotLK HUD band gate (Hand of Reckoning 67485, Hammer of Wrath 48806) asks the client's spell book about a **talent** spell. If the client answers "not known" for a *learned* talent, the mirror stays hidden. Record what the WotLK client answers for those two ids (the band is **WotLK-only** and **off by default** — turn it on in options → Paladin → HUD → Icons to see it). Also record the client's own cooldown lengths for both: the sim models 6 s and 6–8 s, and the HUD reads the client's own number | The gate reads the tri-state `api.is_spell_known_state` (both hiding answers told apart, unknown-hides; `bench/compat_m3_contract_2026-10-20.md` §3.1; `bench/paladin_audit_close_2026-10-20.md` §1.5); **UNCONFIRMED in-client** |

### P12 row — the per-client truth pass's operator-only probes (added 2026-10-20)

Four probes the per-client truth pass could not close offline
(`bench/perclient_truth_final_2026-10-20.md` §6, reconstructed from the publish-gate audit's
C3–C6 rows). **These are NOT §9's own "P9 rows" (the APL utility layer) or "P10 rows" (the
audit-fix wave)** — the two lists reuse the same labels, so read the source tag on each row.
Three of the four live in the class sections: **P9** in §1 step 10, **P10** in §1 step 11,
**P11** in §3 step 8. **P12** is the row below (the spell-data probes and the HUD ownership).

| # | What to confirm | Exact expected outcome | What counts as a defect | Status going in |
|---|---|---|---|---|
| P12-a | **The id form and the return arity** — run on **every** client you can log into. Pick a spell the client **has** (Era/TBC/Wrath: `20308`; on any other client: an id from your own spellbook — **report which id you used**), then run exactly:<br>`/run local n,r,i,ct,mn,mx,sid=GetSpellInfo(<ID>); print("SPELLINFO",n,r,i,ct,mn,mx,sid)` | The line prints **seven values**: `n` = the spell's name, `r` = the rank/subname, `i` = the icon fileID, `ct` / `mn` / `mx` = **numbers** (cast time, min and max range) and `sid` = **the same id you passed**. That confirms the 7-value shape and "the id is the 7th" on that client | `sid` **empty or nil** → the client returns a **shorter** shape and the tree's `compat.lua:157-176` assumption does **not** hold there: record the client and the values that did come back. `ct` / `mn` / `mx` **not numbers** → record the same way. **A probe on a spell the client does NOT have answers nil for every slot and says nothing about the arity** — that is a defect in the probe, not in the client | **UNPROVEN on every client** — the classic global is a C++ API and no branch of the reference repo unpacks 4+ values (`bench/perclient_truth_final_2026-10-20.md` §5). The line prints in the chat frame; keep `/console scriptErrors 1` on |
| P12-b | **The name form** — run both on **every** client:<br>`/run print("SPELLNAME", GetSpellInfo("Fireball"))`<br>`/run print("SOTC", GetSpellInfo("Seal of the Crusader"))` | The **Fireball** line answers a **name** → the classic global takes spell **names** on that client; it answers **nil** → it does not. The **SOTC** line says something only on the classic line (Era/TBC/Wrath) — on Retail/Forever/Cata/Mists the seal does not exist, so only the Fireball line speaks there | Neither line printing at all (the command errored) → record the error text verbatim. A name that is **not** the spell you asked for is a defect — report the exact line | Name-acceptance is **PROVEN on Retail** (the only live global call site on that branch passes a name) and **UNPROVEN from the tree for Era/TBC/Wrath** — the client is the only witness (`bench/perclient_truth_final_2026-10-20.md` §2.4) |
| P12-c | **The Healthstone id on Cata/Mists** — on a **Cata or Mists** client only (on every other client record **N/A**):<br>`/run print("HS", GetSpellInfo(5720), GetSpellInfo(6262), GetSpellInfo("Healthstone"))` | The line names **which of 5720 / 6262 answers**, and whether the **name** "Healthstone" answers and **which id** it resolves to. On the Era/SoD client the client's own data proves **5720 = Healthstone** and **6262 = Minor Healthstone** (a *different* spell) | The **name** "Healthstone" answering **nil** on Cata/Mists → the name-first leg finds nothing there: record the line and say so. A name that resolves to **5720** on Cata/Mists is a finding too — the tree's claim is that the Cata/Mists Healthstone is **6262**, and that claim is **UNPROVEN** until this line comes back | The Era/SoD half is **PROVEN by the client's own data** (`bench/perclient_truth_final_2026-10-20.md` §4.2); the **Cata/Mists** half is **UNPROVEN** |
| P12-d | **The HUD slot ownership — the hunter's slot set per client.** On every client you have, read the hunter's HUD row with **every HUD slot toggle at its default (on)** — the slot toggles ship on (`config_presets.lua:460-461`) — and **report the full slot list** | **Forever (1.60.1): seven slots** — **no Steady Shot** cell (that client has no Steady Shot) and no Kill Command cell. **Mists (5.5.0): eight slots** — **no Raptor Strike** cell (that client's own spell data carries no Raptor Strike id this tree knows). **Cata (4.3.4): nine slots** — the Raptor Strike cell **ships** there, with the client's own rank id **2973** as its icon | A **Steady Shot** cell on the **Forever** client, or a **Raptor Strike** cell on **Mists**, is a defect — the dead-slot filter did not run there. **NOTE (the audit row's wording is coarser than the tree):** the audit's C6 row says "Cata/Mists: no `raptor` slot", but the tree drops that cell on **Mists only** (`classes/hunter.lua:3082-3086`) and **Cata** keeps it with the 2973 icon — so a Raptor Strike cell on **Cata** is **expected**, not a defect. Record what you see either way | The tree's per-family filter is **verified offline** (`classes/hunter.lua:3037-3096`; `bench/hunter_sod_build_2026-10-20.md` §8); the **in-client** slot list is **UNCONFIRMED** |

## 10. Report-back format (append to this file's consumer — do NOT edit this file)

Create a NEW bench file (`bench/live_results_<date>.md` — never overwrite this script):
per client: version, the **whole `/st diag` block** verbatim (the login line, the flags /
modules / ticks / secrets lines, the ids lines, the error-ring lines, any +N count lines) and
the `diag runtime …` counters line, then per class-section checklist with pass / fail /
did-not-see + what was expected
(cite the step number above) + exact observed behavior. Lua errors verbatim or "none".
Close with the U1–U17/OP-1–OP-5 table, **the P8 rows, the P9 rows and the P10 rows** marked
per the row instructions.
Also report the practice results in one block: per class, the rotation-scenario run
(gradeable steps / run grade), **which utility rows appeared in the action strip and which
did not**, the **hold** results (HOLD OK / ILLEGAL CAST counts), every drill's grade, the
**pre-pull** sequence and offsets (§7.9), the **HS/Cleave queue** drill's grades and the
felt window (§7.10), the badge readouts, the Progress page and the sparkline (one line
each), and the design-mode element list (and its **13-or-14** count, §7.8).
Finally, report the **audit-fix wave** in its own block: the druid's press-nothing hold
(§5.6 — what the strip showed, what pressing nothing graded, what pressing something
graded, and the priority drill's result), the **logout-persistence** block (§7.11 — the run
counter, time active, history row and daily streak after logging out and back in), the
**mid-session reset** block (§7.12 — what the XP/streak/stats did after the reset), and the
**paladin strip per family** (§1.9 — which rows each family's strip showed).
Add the two surfaces this pass added: the **trinket gate** (§0.3 — what each trinket slot
showed for a passive stick and for an on-use trinket) and the **warrior's W-21 mirror**
(§2.6 — was it off until you turned it on, did the HUD icon ride the GCD, did the guide's
Sunder icon count the debuff down).
Report the **per-client truth pass** in its own block — these four answers are wanted:
the **Consecration icon press** (§1.10 — the exact grader line and the button labels you saw,
per client), the **Cata/Mists Seal of the Crusader** row (§1.11 — the full paladin button
list per client, and whether a Seal of the Crusader button was present), the **Cata/Mists
shaman common abilities** row (§3.8 — the full shaman button list per client, and which of
the five appeared), and the **P12 row** (§9 — the `SPELLINFO` line verbatim per client, the
`SPELLNAME` and `SOTC` lines, the `HS` line on Cata/Mists, and the hunter's HUD slot list per
client). **N/A with the client name** is a valid answer for a row that does not apply to that
client.

---
*Teams checklist state when this script was written: harness **41/0**, luacheck **2/0 floor**
(83 files), `guide_contract` green; the per-lane mutation proofs stand on `/tmp/opencode`
copies (the central journal's lane table, rows through the Phase-6 closure wave, plus the
2026-10-20 APL utility / residuals lanes and the 2026-10-20 audit-fix wave). Nothing further
is offline-provable — this session is the next evidence.*

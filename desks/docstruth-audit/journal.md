# docstruth-audit journal (filed by orchestrator — proctor has no write tools)

## 2026-10-20 — documentation truth audit (ses_ea616dd2bffemQkB0t3MTrAaWb)

Read-only, every claim in `CHANGELOG.md` / `README.md` / `TESTING.md` /
`bench/live_test_script_2026-10-19.md` checked against the tree (51 numeric/feature claims
verified individually).

VERDICT: FINDINGS 18 — 5 HIGH, 6 MEDIUM, 7 LOW. The docs are largely honest (every wave section
is marked "verified offline, UNCONFIRMED in-client"; the big numbers — 25 drills, the XP curve,
mastery tiers, 67 wanted ids, the utility ids — all verify TRUE). The failures concentrate in the
**operator's script**, which names five things the build does not have.

### HIGH (the operator would file a phantom defect)
- F-1 script §6.1 — tells the operator to confirm the ABSENCE of a rogue SnD prompt; the build ships
  an ARMED SnD upkeep (slot `snd` at `classes/rogue.lua:877`, rotation row `:2416`,
  `rogue_guide.lua:1123-1155`). Rewrite as the shipped contract.
- F-2 script §7.9 — invents an Era hunter pre-pull (Aspect of the Hawk @-10, Aimed @-3.5);
  `ST.HUNTER.PRACTICE_PREPULLS` has TBC/SOD/FOREVER only (`classes/hunter.lua:3419-3462`), and the
  drill answers UNKNOWN on Era (`:4406-4409`) — which is correct, not a defect.
- F-3 script §6.2/§7.9 — two superseded names: the rogue's Forever pre-pull is **Blade Flurry 13877
  @-2** (not "Blood Fury"), and the builder chain is `{Saber Slash, Mutilate, Hemorrhage}` with a
  family gate (`classes/rogue.lua:264`, `rogue_guide.lua:640-666`) → TBC resolves **Hemorrhage**.
- F-4 script §0 — **`/st diag verbose` is not a command.** The handler matches only
  `"" / practice / design / diag` (`main.lua:2013-2046`); `/st diag` IS the verbose report. The
  operator loses the highest-value paste of the session.
- F-5 `TESTING.md:31-37` — the expected diag shape omits the **ticks** line and mixes the login
  one-liner with the verbose report (`diag.lua:681-709`, `main.lua:2039`).

### MEDIUM
- F-6 CHANGELOG:607-610 — the paladin pre-pull list names "Divine Storm 20920 / Holy Shock 20308";
  the tree labels 20920 **Seal of Command** and 20308 **Seal of the Crusader**
  (`classes/paladin.lua:4688-4702`; bench C3).
- F-7 CHANGELOG:531-535 — "the warrior included" in the no-drill refusal is superseded (the warrior
  publishes six drills).
- F-8 "13 design targets" is class-dependent — a **druid** registers a 14th (Combo Points pips,
  `classes/druid.lua:1506-1522` → `bars.lua:1172-1195`).
- F-9 script §7.2/§7.9 — the paladin's utility layer "was still landing" (it landed: 17 rotation
  rows) and the pre-pull list shows 2 rows where the tree ships **11**; 10301's name is CONFIRMED.
- F-10 two shipped surfaces have **no operator step**: the usable-only trinket gate and the warrior's
  W-21 HUD mirrors (the TBC Sunder mirror is visible by default).
- F-11 the script's file:line citations have drifted (diag WANTED_IDS 74-96 not 68-89; the error
  ring 527-553; the rogue "slot table" line is the builder gate).
- F-12 script:678 — JotC 21183 over-claims in-client proof (web-CONFIRMED only).

### LOW
F-13 README/TESTING client lists omit the **Cata (40402)** and **Mists (50500)** flavors;
F-14 a now-void correction notice in the CHANGELOG; F-15 the `hunter_multi_target` copy marker
changed; F-16 the note/refusal strings differ (same behaviour, two strings); F-17 "pips 10->12"
matches no shipped number; F-18 dated per-suite check counts in dated sections.

### Shipped surfaces the script does not cover
usable-only trinkets; the warrior's W-21 HUD mirrors; the rogue SnD prompt (mis-stated as an
absence); the rogue builder chain (mis-stated).

### Limitation
`/home/sam/wow-ui-source` carries no spell-name data in Lua form, so F6 is the doc/tree
DISAGREEMENT — the doc must match the tree's labels, or a code-side correction must be raised.

## 2026-10-20 — the fix pass (F-1/F-2/F-3/F-4/F-5/F-8/F-9/F-10/F-11/F-12/F-13/F-16)

- **Worked on:** the three in-scope doc files only — `README.md`, `TESTING.md`,
  `bench/live_test_script_2026-10-19.md` (extended in place; no second script). Every claim
  was re-read in the tree before it was written down.
- **HIGH (5) — closed:**
  - **F-4** `/st diag verbose` does not exist. The handler matches only `` / `practice` /
    `design` / `diag` (`main.lua:2013-2046`) and `/st diag` IS the verbose report
    (`main.lua:2038` → `diag.report(self, true)`). Script §0 step 2 now says "run `/st diag`
    and record the whole block"; the old step 3 was folded in and its slot now carries the
    new trinket step; step 6 still ends with "run `/st diag` again".
  - **F-1** §6.1 no longer asks for the ABSENCE of a rogue SnD prompt. The shipped contract is
    now written out (armed `snd` slot `classes/rogue.lua:877`, rotation row `:2416`, engine
    `rogue_guide.lua:1123-1155`; prompt when the buff is down or inside the family's refresh
    window and CP is at/above the family minimum — Era 1/3, TBC 2/0, SoD 4/1, Wrath 1/1,
    Forever 1/0; a MISSING prompt while the buff is down is the defect).
  - **F-2** §7.9's invented Era hunter pre-pull is gone: `ST.HUNTER.PRACTICE_PREPULLS` carries
    TBC/SoD/Forever only (`classes/hunter.lua:3419-3462`) and the drill answers UNKNOWN on Era
    (`:4406-4409`) — correct, not a defect. The real per-family rows are listed.
  - **F-3** §6.2/§7.9 now carry the tree's names: the rogue's Forever pre-pull is **Blade
    Flurry 13877 @-2** and the builder chain is `{Saber Slash, Mutilate, Hemorrhage}` with the
    family gate (`classes/rogue.lua:264`, `rogue_guide.lua:630-666`) → TBC resolves
    **Hemorrhage**.
  - **F-5** `TESTING.md` Step 0 now separates the addon's own **login one-liner** (printed at
    login, `main.lua:673-677`) from the `/st diag` verbose block, and the expected shape
    carries the **ticks** line (`diag.lua:681-709`) plus the `diag runtime …` line.
- **MEDIUM (7) — closed:**
  - **F-10** two new operator steps: the **usable-only trinket gate** (script §0.3 + a
    TESTING.md bullet) and the **warrior's W-21 Sunder mirror** (script §2.6 + a TESTING.md
    bullet). NOTE: the tree says the mirror **ships OFF** (`hud_show_sunder = false`,
    `config_presets.lua:1339`; it hides unless the toggle reads exactly `true`) and is
    **display-only** — no GCD swipe, no cooldown count; the *guide's* Sunder icon is the one
    that counts the debuff down. The brief's "visible by default / counting the debuff down"
    did not match the tree, so the docs follow the tree.
  - **F-9** §7.2's paladin paragraph no longer says the utility layer "was still landing": it
    landed — the rotation table carries **17** rows, three of which (Judgement of Wisdom,
    Holy Strike, Divine Favor) have no engine arm and stay out of the panel's button
    vocabulary. §7.9's paladin row is now the table's **11** rows and 10301 is
    **Retribution Aura, NAME CONFIRMED**. §7.9 also stops claiming the paladin has no
    pre-pull drill — it ships `paladin_prepull` (the seal and its lead).
  - **F-11** drifted citations re-pointed: WANTED_IDS `diag.lua:74-96`; error ring
    `:527-553` (cap `:543-545`, handler `:556-594`); MAX_LINES `diag.lua:60,640-671`; the
    rogue "slot table" line was the **builder gate** (`classes/rogue.lua:594-604`) → the slot
    table is `:868-881`; the JotC bar `classes/paladin.lua:2508-2537,2670-2688`; the hunter's
    steady rank `classes/hunter.lua:70-76,2044-2047`; the delay budget `nextaction.lua:499-504`;
    the SoD FCFS order `nextaction.lua:984`; the template preview `hud.lua:1120-1158`; the
    VR bypass `classes/warrior.lua:3623-3641` + `warrior_guide.lua:1581-1589`; the guide
    toggle `nextaction_ui.lua:441`; the HUD toggles `option_tables.lua:1349,1866-1869`.
  - **F-12** the U11 row's JotC claim is now **web-CONFIRMED** (wowhead / warcraft.wiki) with
    the in-client shape **UNCONFIRMED**; §1.3 also states that the JotC bar ships **off**
    until the operator turns it on.
  - **F-8** the design-target count is class-dependent: **13**, or **14 on a druid** (the
    Combo Points pips, `classes/druid.lua:1506-1522` → `bars.lua:1168-1195`) — said in the
    script (§7.8) and in TESTING.md.
  - **F-13** `README.md` and `TESTING.md` now list **Cata `40402`** and **Mists `50500`** and
    say why they are not supported: those two TOC flavours ship **without**
    `LibClassicSwingTimerAPI`, so they load with the inert stand-in (bars static, the
    one-time "Swing timer bars are unavailable on this client; range and GCD features remain
    active." notice, `main.lua:663`).
  - **F-16** the two strings are quoted exactly and the docs no longer say they are the same:
    the refusal is "Practice scenario is not available on this client (no live swing engine)."
    (`practice_ui.lua:5459-5460`) and the Practice-page note appends " The rotation scenario
    cannot run on this client (no live swing engine)." (`option_tables.lua:486-490`).
- **Out of scope, untouched:** `CHANGELOG.md` (a sibling lane owns it), every `.lua`, every
  other bench file, the TOCs, the versions. No git commits. No new bench artifact was written
  — the in-scope output is the three doc files and this journal.
- **Current state:** the three files are edited and the offline harness is green (41/0 steps,
  luacheck 2/0 in 83 files — re-run after the edits, docs only). No in-client claim is made
  anywhere in the three files; every row this pass touched stays UNCONFIRMED.
- **Next step:** the orchestrator owns validation — an in-client pass over the revised script
  (§0, §2.6, §6.1, §6.2, §7.2, §7.8, §7.9, §8) is what turns the UNCONFIRMED rows into
  evidence. A second docs-truth lane should re-audit the **CHANGELOG** (F-6/F-7/F-14/F-15/
  F-17/F-18 were out of this lane's scope) once the sibling lane releases it.


# In-client test script

Purpose: turn one scarce test session into attributable evidence. Every failure mode in this
addon is silent (a library that never reports ready is disarmed by a 5-second deadline with a
single chat notice; nil-guards render nothing; a guide that cannot decide says nothing), so
"it loaded fine" is not a result. Write down what each client prints and what each visual does.

Supported clients under test:

| Client | Interface | Swing engine expectation |
| :--- | :--- | :--- |
| Classic Era / Season of Discovery | `11509` | vendored `LibClassicSwingTimerAPI` |
| TBC Anniversary | `20506` | vendored `LibClassicSwingTimerAPI` |
| WotLK Titanforge | `38002` | vendored `LibClassicSwingTimerAPI` |
| WoW Forever | `16001` | native `PLAYER_SWING` (`swing_source.lua`) |
| Retail / Live (Midnight) | `12.1.x (120100, 120105)` | inert stand-in (bars intentionally static) |

The build also ships two **Cata/Mists flavours** — `SwedgeTimer_Cata.toc` (`40402`) and
`SwedgeTimer_Mists.toc` (`50500`). They deliberately ship **without**
`LibClassicSwingTimerAPI` (the library is not in those TOC variants), so on those clients the
addon loads with the **inert stand-in** — the same shape as Retail: the bars never move and a
one-time notice says "Swing timer bars are unavailable on this client; range and GCD features
remain active." (`main.lua:12,31-44,663`). They are **not supported clients**: there is no live
swing engine, so the rotation scenario is refused there too. Do not file a defect for a static
bar on Cata/Mists — record it and move on.

---

## Before the first launch

1. **Back up anything you care about**: copy `WTF/Account/<you>/SavedVariables/SwedgeTimerDB.lua`
   (and ideally the whole `WTF/` folder) plus the addon folder itself. The first login writes
   SavedVariables; nothing else can un-write that.
2. In game, run: `/console scriptErrors 1` — so any Lua error is visible instead of swallowed.
3. Know the version under test (top of `main.lua` / the TOC) and note it below.

## Step 0 — every client, every time (2 minutes)

1. Log in. Expect **no Lua error** and the bars on screen.
2. The addon prints a **login one-liner by itself at login** (`main.lua:673-677`) — record it
   verbatim:
   ```
   SwedgeTimer diag: family=WRATH iface=38002 version=2.1.1 engine=vendored-lib lrc=ready lcd=present ldb=pending guides=PALADIN:on WARRIOR:on DRUID:on SHAMAN:on HUNTER:on ROGUE:on
   ```
   Then run **`/st diag`**. There is **no `verbose` sub-command**: the slash handler matches only
   `` / `practice` / `design` / `diag` (`main.lua:2013-2046`), so `/st diag` **is** the verbose
   report. Expected shape (values change per client):
   ```
   SwedgeTimer diag: family=WRATH iface=38002 version=2.1.1 engine=vendored-lib lrc=ready lcd=present ldb=pending guides=PALADIN:on WARRIOR:on DRUID:on SHAMAN:on HUNTER:on ROGUE:on
   SwedgeTimer diag: flags stl_ready=true llm_ready=false lrc_ready=true lrc_unavailable=false deadline=no init=yes
   SwedgeTimer diag: modules practice=yes hud=yes rotation=yes design=yes providers=6/6
   SwedgeTimer diag: ticks on=yes mainhand=<count> offhand=<count> ranged=<count or ?> cpu=<n.nn>s
   SwedgeTimer diag: secrets api=no
   ```
   followed by the wanted-id lines, the error-ring lines (if any), any `+N more` count lines and
   the `diag runtime …` counters line. The **`ticks`** line is part of the verbose block
   (`diag.lua:681-709`) — a report without it is not the report this script describes.
   - `engine=` must match the table above for the client you are on.
   - The guides line names **all six classes** (PALADIN, WARRIOR, DRUID, SHAMAN, HUNTER,
     ROGUE) and `providers=6/6` — the rogue guide provider is present. On a fresh profile
     all six read `on` (every guide ships enabled); a class reads `off` only when its
     `nextaction_enabled` toggle was set to exactly `false`. A `5/5` provider count or a
     five-class guides line means the build is not the one this script describes.
   - `lrc=fallback` means the range library never reported ready (the designed fallback; record it).
   - `deadline=fired` means a library missed the 5s window — note it, it is not automatically a bug.
   - `secrets` is the Mainline secret-value readout: `api=no` on classic clients; on Retail/Forever it lists
     which restricted reads (`restrictions`, `cd`, `aura`, `power`, `stats`, `cast`) come back opaque.
     Record it verbatim — it decides whether the silent degradation paths are active in your session.
3. `/reload`, then **cast/attack within 5 seconds** — this used to be a crash window; expect none.
4. Open `/st` (options) — every section renders; `/st design` toggles the grid; `/st practice` opens
   the panel (paladin).
5. Run `/st diag` again and confirm it still matches.

Record: every diag line per client, verbatim (including the secrets line).

## Step 1 — per client checklist

### Classic Era / SoD (11509) and TBC Anniversary (20506)
- [ ] Swing timer moves; mainhand/offhand/ranged bars behave; GCD marker visible.
- [ ] Paladin: twist window band appears in the last ~0.4 s of a swing; a successful twist shows
      "Successful TWIST!" (classic line only — on WoW Forever expect the
      "twist scoring: classic-line only" notice instead, never a 0/0 score with no explanation).
- [ ] Anniversary R1 check (settles the string-vs-numeric question): `/dump` the `spellId`
      slot type on a `COMBAT_LOG_EVENT_UNFILTERED` SPELL_DAMAGE / SPELL_MISSED event —
      record whether it is a number or a localized-name string.
- [ ] Paladin guide (on by default; toggle it in options): CS/Command/Blood/twist icon
      switches; HOLD/RIDE appears.
- [ ] **Paladin practice strip, per family — no button the rotation cannot ask for.** On
      **TBC** the practice strip must offer **no "Hammer of Wrath" button**: the TBC
      rotation can never ask for it (the engine's execute arm is Era/Forever only), and
      pressing it used to grade out-of-order → F for a spell the rotation never wanted.
      On **Era** the strip's rotation part drops Consecration and Exorcism (the Era APL
      carries no filler row) — those presses stay reachable through the panel's
      asked-for vocabulary, so check that the panel still offers them when the engine
      asks. Record which rows each family's strip shows.
- [ ] Paladin P3: under a live Bloodlust/Heroism the twist window narrows (0.6x); Era never narrows.
- [ ] Hunter H2: under a live Bloodlust/Heroism the Steady-spam cue fires; Era never fires.
- [ ] Seal swipe on the guide's Command/Blood icons reads ~30 s (LibClassicDurations).
- [ ] Shaman: weave marker shows; cast a Lightning Bolt that outlasts the swing — the spark must
      travel one way only (never jump back), and turn red when it would clip.
- [ ] Warrior: queue Heroic Strike with low rage → bar turns the insufficient-rage colour; Blood
      Surge proc → glow starts once and stops cleanly.
- [ ] Druid: Maul queue tint; form colours in cat/bear/travel; energy tick column in cat form.
- [ ] Hunter: auto-shot cycle syncs the ranged bar; queue Raptor Strike → yellow tint; the hunter
      cast bar shows the "Auto Shot" window label in the last ~0.5 s + latency.
- [ ] Hunter shot guard (in-client): at range, auto-shooting must **not** move the mainhand/offhand
      bars; a real melee swing must still start mainhand. `/st diag` prints the wire counters as
      `swing_mainhand=<start>/<update>/<stop>` (same for offhand/ranged) plus `swing_last=<kind>:<hand>:<age>s`;
      `swing_mainhand`'s START count must stay flat between real melee swings (an Auto Shot must not bump
      it). On Wrath/Titanforge the stock library's own Auto Shot reset entry is the documented residual:
      record whether the melee bars still restart there.
- [ ] Ranged-distance bar (in-client): full at melee range, empty past **35 yd** for a hunter (**30 yd**
      for other classes), with the exact-yards label plus **MELEE / IN RANGE / OUT**. It hides with no
      target or an unreadable distance (never paints a false 0). Hunter default is on; other classes
      opt in.

### Rogue (Era / TBC / Wrath / Forever — all in-client, UNCONFIRMED; nothing below is proven offline)
- [ ] (in-client) Energy tick accuracy: the rogue energy-tick spark tracks the real 2 s tick
      against the Yam overlay; pooling tint follows the 65/85 bands; Combat-Potency grants
      never re-anchor the tick (ambiguous tick hides, never guesses).
- [ ] (in-client) Era SS-window feel: with a sword mainhand on Era, queue Sinister Strike in the
      0.1–0.2 s post-mainhand-swing window; confirm the window band reads correctly and never
      appears on TBC or later.
- [ ] (in-client) SnD / Rupture upkeep: HUD slots count down live, glow in the final 3 s when
      the glow toggle is on; the guide's POOL/NOW prompt matches energy, combo points and
      remaining durations; unknown reads render "…" instead of advice.
- [ ] (in-client) Expose Armor juggle: the EA-duty cue refreshes at the configured threshold;
      Shiv upkeep and the Thistle Tea deficit cue fire at the right energy/CP state.
- [ ] (in-client) Vanish / Overkill window: confirm the expected cue behaviour on each client
      (UNCONFIRMED — record exact behaviour per client, including no-cue if that is what happens).
- [ ] (in-client) Thistle Tea count probe: confirm whether the item-count read returns a usable
      number on each client (UNCONFIRMED — record per client).
- [ ] (in-client) Poison reminder: the mainhand/offhand poison reminder shows when a weapon
      enchant is missing; poison charge counts are NOT rendered (UNCONFIRMED probe shape —
      record whether any client exposes charges).

### WotLK Titanforge (38002) — the full pass
Everything above (including the R1 `/dump` and the P3/H2 lust checks), plus:
- [ ] Paladin: JotC mini-bar counts down from a Judgement and refreshes to 20 s on a
      max-rank melee landing (lower ranks stay fixed at 10 s, never refresh).
- [ ] Warrior: bank cue appears when banked rage is available (toggle-gated);
      Battle Shout badge counts down; Shield Block bar appears while buffed.
- [ ] Druid: TF/Berserk HUD slots show and glow while ready in combat; on runeless
      Era Mangle hides and the row reflows closed (no gap); re-enable/revive closes
      the gap without a settings change; a hide/show flip mid-combat defers the
      reflow until combat exits.
- [ ] Warrior: apply Rend/Sunder/Deep Wounds to a dummy → stacked bars above the mainhand bar;
      Sunder shows its stack count; Shield Block bar appears while buffed; casting Slam shows the
      "SLAM X.Xs" bar; get dodged → the Overpower flash ("OP") appears and clears when you cast it.
- [ ] Druid: Mangle/Rip/Rake bars count down with a glow in the last 4 s; refresh thresholds fire.
- [ ] Shaman: Windfury ICD strip (red → orange → green) after a swing; Flame Shock target bar;
      `SS`/`SR` badges; Lightning Shield charge row; 2-3-stack weave icons sit in the
      safe-start zone band with effective cast times; a cast started past its safe start
      shows red icon/number (clip state); Flurry ICD readout and DW SYNC/DESYNC badges
      track the offhand.
- [ ] Hunter: the 4-state range helper strip (melee/sweet spot/ranged/OOR), Rapid Fire bar, aspect
      icon, and the safe-to-move cast zone (green/red threshold marker); Aimed Shot re-points
      the cast bar; Steady/Aimed casts take over the cast bar from the Auto-Shot window.
- [ ] Cooldown HUD (enable): CS/Judgement/Consecration/Exorcism swipes, trinket cooldown/proc,
      Wings glow when ready, blue/red tints for no-mana / out-of-range.
- [ ] Rotation label (enable): shows `2/3`-style text; all four formats; drag + lock.
- [ ] Guides: enable paladin/warrior/druid/shaman/hunter/rogue one at a time and verify
      their prompt rules (see the class-specific criteria in the release notes).
- [ ] Practice: start a fight, make a twist, stop; enter combat mid-session → "paused", leave →
      resumes with timers shifted, no instant expiries; the panel reset button visibly
      re-anchors the panel; the timeline drags and persists, and its X button closes it.
- [ ] Practice timeline (in-client): `/st practice` shows BOTH frames — the moving cue strip near the
      top of the screen and the trainer panel. The strip is a full-width band (the track spans the
      client; the 600 px track is only the fallback when the client reports no screen width) with a left
      rail (icon + name per lane: SoB / Melee / CS / Consec / SoC / Judge on the paladin), a ruler whose
      `m:ss` labels and full-height second gridlines scroll under the fixed playhead, the rotation band
      (label + sequence icons) top-centre, and banded 30 px lane rows.
      The paladin session opens **stopped**: the cues, ruler and playhead do not move until **Start
      Fight**; **Stop Fight** freezes them in place; a second Start re-anchors and runs them again.
      Cues cross the playhead while the fight runs. The strip's **X** hides it (the next fight or the
      **Timeline** toggle brings it back); **Timeline** opens the old post-fight log, and closing it
      brings the strip back while the session still runs.
- [ ] Practice panel chrome (in-client): the panel reads like the reference — bind hint under the grid
      ("Right-click icon to map to action bar"), a **(Reset)** link under it that restores the session
      keybinds (labels go back to 1-9), a hairline between each block, **Bloodlust** and **Haste Pot** as
      two equal halves, then the **Practice Rotation** picker (Raid Pull / 1-2 / 2-3 / 2-4), **Start
      Fight** and **Timeline**. The fight timer, score, resource, DST toggle and the live hint sit below
      that block. A class drill panel (hunter / shaman / rogue / druid / warrior) shows its own icon grid
      with the same bind hint but no **(Reset)** link and no separators, and no DST/rotation rows.
- [ ] Practice XP by timing (in-client): with practice open but no fight running, the XP bar does not
      move; after **Start Fight**, a correct timed press (a twist on the swing, a class drill's graded
      cast) adds XP immediately (badge/Progress page), and a missed or idle press adds nothing.
      Closing the options window leaves practice running; only the practice panel's X stops it. On the
      options page the entry reads **Open Practice Panel** and raises the trainer instead of stopping it.
- [ ] Bar backdrop (in-client): a fresh profile **and** a profile migrated from 2.1.2 both render an
      opaque bar backdrop (alpha 1.0). A hand-set custom colour and the **Classic Retro** preset keep
      their saved alpha — the one-time migration raises only the untouched old default.
- [ ] Practice drills, all six classes (start each three ways: `/st practice`, the class-panel
      Start/Stop toggle, the top-level Practice toggle — one session; starts only out of combat).
      Every drill grades S–F into the shared running score with persistent bests; unknown
      reads score nothing, never a guess. The per-class drill sets this build ships:
      **paladin** `paladin_fcfs_priority` (FCFS priority order) / `paladin_prepull`
      (prepull seal) / `paladin_judge_fit` (Judgement fit) — and the paladin's drill list
      **leads with the twist timing drill** (the twist minigame is the paladin's own; press
      it and the panel hands over to the twist session); **warrior** `warrior_core_order`
      (core rotation) / `warrior_ww_delay` (core window) / `warrior_sunder_upkeep`
      (debuff upkeep) / `warrior_execute_burn` (execute burn) / `warrior_hs_queue`
      (the HS/Cleave queue window) / `warrior_prepull` (the pre-pull opener); **hunter**
      `hunter_shot_order` (shot priority) / `hunter_weave_clip` (the clip) /
      `hunter_kill_command` (cooldown pops) / `hunter_prepull` (the opener); **rogue**
      `rogue_finisher_order` (finisher order) / `rogue_cp_finish` (combo-point decision) /
      `rogue_snd_upkeep` (debuff upkeep) / `rogue_opener` (the opener); **druid**
      `druid_finisher_order` (the cat priority) / `druid_powershift_rework` (the shift rule,
      re-sourced) / `druid_roar_upkeep` (the Roar upkeep) / `druid_bite_execute` (the
      execute); **shaman** `shaman_enh_priority` (enhancement priority) /
      `shaman_mw_weave` (the stack decision) / `shaman_stormstrike_hold` (the Stormstrike
      decision) / `shaman_totem_upkeep` (the totem upkeep).
      The shipped built-in drills stay available (the twist sim, the hunter forced-move
      windows, the warrior Execute phase, the Era-only rogue SS-after-swing window) — but
      three of them are **superseded** by the class drill that owns the same skill, so the
      grade you see is the class drill's: the druid shift grades on the sim's trigger (not
      the old 20-energy rule), the shaman weave adds the Maelstrom-stack condition (a weave
      below the stack floor is an F), and the warrior Execute burn grades the press.
- [ ] Practice mode select (options → Practice → "Practice mode"): `class` (default, the
      shipped per-class session), `scenario` (the class's own rotation end to end) and
      `drills` (the class's focused drill list, one button each). The note under it states
      whether the class ships a rotation scenario and how many focused drills it has —
      expect "yes" for all six classes, and the drill counts **paladin 3, warrior 6, hunter
      4, rogue 4, druid 4, shaman 4**. An unset or unknown value must fall back
      to the class session, never to another class's drill.
- [ ] Rotation scenario, all six classes: set the mode to `scenario`, start the session, and
      cast what the panel asks for. The run is ten decisions; the panel's step window is
      3 s and an expired step closes as a **miss**. A correct cast grades S, a wrong or
      out-of-order cast grades F, and a step the class cannot decide (a nil step) records
      **no attempt** — it must never show a wrong grade. The run summary grades
      S 0 mis-picks / A 1 / B 2 / C 3 / D 4-5 / F 6+.
- [ ] Rotation scenario — the utility layer. The scenario carries the class's **full** sim
      priority list, so the action strip must show the utility rows too, per family:
      **warrior** the stances (Battle Stance / Berserker Stance), Bloodrage, Battle Shout,
      Recklessness, Death Wish; **hunter** Rapid Fire, the Serpent Sting upkeep, the aspects
      (Viper / Hawk / Dragonhawk / Falcon) and Kill Shot; **rogue** Vanish, Preparation,
      Premeditation; **druid** Cat Form, Leader of the Pack, Innervate; **shaman** Strength
      of Earth, Mana Spring, Frost Shock, Bloodlust; **paladin** Hand of Reckoning and
      Hammer of Wrath (WotLK rows). A family that does not carry a row must never show it.
- [ ] Rotation scenario — a **hold** is a decision, unknown is not. When the class's own
      engine says hold (the rogue's POOL, the shaman's RIDE/WAIT, the hunter's RIDE/HOLD,
      the paladin's RIDE / "nothing is ready", the warrior's RIDE / HOLD), the panel
      must show the hold and the class's own reason. Casting during the hold is an
      **illegal cast** and grades F; doing nothing is correct and records **no attempt**.
      The **druid** has one press-nothing hold — the bear chain's queued **Maul**, whose
      guide verdict is `RIDE` — so it must read as a **hold**, never as a press; the
      druid's other nine guide holds name a spell to press, so those stay actions.
      (The warrior's CANCEL cue names the Execute, so it is an **action**, not a hold.)
- [ ] Rotation scenario — the **druid's press-nothing hold** (the fix that made the bear
      chain's queued Maul grade as a press). In **bear form with a queued Maul**: the
      scenario step must show the **hold** (the guide's `RIDE` reason), the strip must
      offer **no "ride" button**, and pressing **nothing** must grade correct with
      **no attempt** — no points, no streak, no mastery tick, and the run's mis-pick
      count unchanged. A "ride" button in the strip, or points for idling, is a defect.
      Pressing **anything** during the hold must read **ILLEGAL CAST** and grade F.
      The druid's priority drill (`druid_finisher_order`) must grade nothing on a hold
      and bank **no mis-pick** for it.
- [ ] Drill list — the pick channel. A drill that needs your choice (the priority-order
      drills) grades the **action you pressed**: press one of the class's action buttons
      first, then the drill button. A drill press that answers UNKNOWN after a correct
      action press is a defect, not a client quirk.
- [ ] Class session routing: the **class session** (the default mode) must start the class's
      own drill and grade through it — the shaman and the druid included, whose sessions
      used to be unreachable and whose panel icons were silent no-ops. A drill cast with no
      session at all must print a refusal, never do nothing quietly.
- [ ] Scenario row hygiene: across a full ten-step run the action/drill strip must not grow —
      one set of buttons, reused, not a pile. (The row used to rebuild its buttons every step
      and only hide the old ones.)
- [ ] Warrior HS/Cleave **queue** drill (`warrior_hs_queue`): with an offhand weapon, queue a
      Heroic Strike and grade the press. The window is the gap between the mainhand's last
      swing and the offhand's next swing; the grade is S ≥ 250 ms, A ≥ 150 ms, B ≥ 80 ms,
      C ≥ 20 ms, D inside the window, F outside it. Record the felt window — the in-client
      queue-lift timing is **UNCONFIRMED** (the sim's 250 ms is its own reaction-time model,
      not a client fact).
- [ ] Pre-pull phase: the **pre-pull** rows live in their own per-class table and are graded
      by the pre-pull drill, never by the combat rotation. Run the warrior's
      `warrior_prepull`, the hunter's `hunter_prepull` (the opener), the rogue's
      `rogue_opener` and the paladin's `paladin_prepull` (the seal and its lead). Record the
      order and the offsets each class asks for.
- [ ] Retail gate: on a client with the inert swing-engine stand-in the rotation scenario is
      **refused** with the message "Practice scenario is not available on this client (no live
      swing engine)." (`practice_ui.lua:5459-5460`), and the Practice page's note appends
      " The rotation scenario cannot run on this client (no live swing engine)."
      (`option_tables.lua:486-490`). Same behaviour, **two different strings** — quote each
      exactly. It must not produce ten unknown steps.
- [ ] Progress page (options → Progress): the level and renown line, the XP bar, the
      per-drill mastery table (tier + mastery % + attempts + accuracy), the achievements list
      (locked and unlocked), the stats summary (runs, attempts, accuracy, rolling-20, last
      session, time active, best score, best grade, best streak) and the all-classes line.
      It writes no settings key of its own; the reset asks twice and the cancel works.
- [ ] **Session persistence across a logout.** Run a practice session, grade a few attempts,
      then **log out of the game and log back in**. The Progress page must still show the
      session's **runs** counter, its **time active**, its **history row** and its **daily
      streak** — the completion bonus, the streak, the run, the time active and the bounded
      history row are all written at logout. A logout that loses them is a defect.
      **Log out — do not `/reload`.** A UI `/reload` fires **no** `PLAYER_LOGOUT` and writes
      **no** SavedVariables (the client serialises them at logout only), so a mid-session
      reload loses the in-flight session whatever the addon does. That is client behaviour,
      not a bug to chase in-client — but it means a reload is **not** a valid persistence
      test.
- [ ] **A mid-session Progress-page reset leaves no half-state.** Start a session, grade a
      few attempts, then press the Progress page's reset **while the session is still
      running** (answer the confirm). Then grade another attempt: the XP, the streak and the
      stats must be **recorded again** — the score moved but the XP, mastery, streak, stats
      and badge did not, silently. The badge must show only the post-reset XP (the erased
      XP must not stay on the "+N XP" line). The session itself keeps running — the score,
      the simulation and the panel are untouched.
- [ ] Stats frame (the Progress page's "open stats" button): the accuracy **sparkline** over
      the last 50 sessions, the per-drill table, the per-class table and the session history
      (newest first, wheel scrolled). The Scope button cycles the classes that have data and
      the account scope; the frame is built on the first open and hidden afterwards.
- [ ] Panel level badge: on a fresh profile it is drawn under the practice panel (level,
      XP into the level, the level bar, the session XP). The Progress page's badge toggle
      turns it off, and a saved `false` must survive a reload. The level-up and achievement
      chat notices ride the same toggle.
- [ ] Design mode: `/st design` lists all **13** targets — 3 swing bars, seal icons,
      Successful twist text, Cooldown HUD, Rotation label, Next action guide, Practice
      panel + rotation display + timeline, Hunter shot report, Warrior Execute report —
      and every listed element drops where dragged; the two report targets appear only
      while their report frame is shown. The practice level badge is **not** one of the 13
      targets — it hangs under the panel and is not draggable.
      **The count is class-dependent: a druid registers a 14th** — the **Combo Points** pips
      row (`classes/druid.lua:1506-1522` → `bars.lua:1168-1195`). Expect **13 on every other
      class** and **14 on the druid**; record the count you actually saw.
- [ ] **The trinket slots — the usable-only gate.** All six classes ship two trinket slots
      (`hud_show_trinket1` / `hud_show_trinket2`, on by default). A slot renders **only when
      the trinket has a usable effect** (`hud.lua:319-350,735-746`):
      - a **passive stat stick** must **NOT** render in the slot (the client's item cooldown
        reports it disabled);
      - an **on-use trinket** must render and **count its cooldown down** while it is on
        cooldown;
      - a **proc trinket** renders while its buff is up, then shows its internal cooldown as a
        reversed swipe;
      - an **empty** slot renders nothing, and an **unreadable** effect hides the slot — an
        unknown is never rendered as "usable".
      Swap the two trinkets and record what each slot shows.
- [ ] **The warrior's W-21 HUD mirror (the Sunder upkeep slot).** On **TBC** the warrior's HUD
      row is the six core abilities **plus the Sunder Armor mirror**
      (`classes/warrior.lua:4050-4056,4090-4105`), and the **guide** row carries the matching
      Sunder slot. The mirror **ships off**: it is hidden unless `hud_show_sunder` reads
      **exactly `true`** (`false` and `nil` both hide — `config_presets.lua:1333-1339`,
      `classes/warrior.lua:4262-4281`); turn it on in options → Warrior → HUD, or pick the
      **W-T2 "Full + Trinkets"** template, which switches it on. Once on, the icon is
      **display-only**: Sunder has no cooldown of its own to ride, so it must **never** ride
      the GCD swipe and never count a cooldown. The **debuff countdown** lives on the
      **guide**'s Sunder icon — its swipe follows the upkeep window the class feeds
      (`classes/warrior.lua:3252-3253,3737-3747`), and that window is fed only on TBC/Forever.
      On Era/SoD expect no Sunder row at all.
- [ ] Spell state queries on **TBC Anniversary and WotLK Titanforge** (in-client check, **NOT proven
      offline**): state queries use localized spell names first, with the id kept as the fallback.
      Record `/st diag` (the `family=` and `ids` lines) and any guide or state behaviour that looks
      id-only.

### Enemy swing (classic line only: Era / TBC / Wrath / Cata / Mists)
- [ ] With `enemy_swing_enabled` on and a hostile target selected: the enemy swing bar
      moves on target swings; with no hostile target (or on Forever / Retail) nothing
      draws and nothing errors.

### WoW Forever (16001)
- [ ] Bars move — driven by the native `PLAYER_SWING` events (no classic combat log).
- [ ] Paladin: the twist band shows (Mainline-code client, but the swing engine runs here);
      no twist *attempt/success* feedback (no combat log) — expected.
- [ ] Warrior: no Overpower flash (no combat log) — expected.
- [ ] Range: may work through the interact-distance checkers or fall back with a one-time notice —
      either is fine; record `lrc=` and whether range text ever fills.
- [ ] Shaman weave, hunter cast bar, druid trackers and the guides all behave as on WotLK.

### Retail / Live (12.1.x — 120100, 120105)
- [ ] Load on each live patch (12.1.0 and 12.1.5) — **no out-of-date flag**, no Lua errors.
- [ ] Load, `/reload`, open options — **no Lua errors**.
- [ ] A one-time notice says the swing timer bars are unavailable (inert stand-in) — expected.
- [ ] HUD, rotation label, design mode and the options UI all work; bars deliberately do not move.
- [ ] Range: the library no longer errors at load; it may work (interact distances) or fall back with a
      one-time "range checking unavailable" notice — either is expected, errors are not.
- [ ] `UnitPower`-based features (rage tints, guides) do not error even though no swing fires.
- [ ] The **rotation scenario is refused** with the message "Practice scenario is not available
      on this client (no live swing engine)." (`practice_ui.lua:5459-5460`), and the Practice
      page's note appends " The rotation scenario cannot run on this client (no live swing
      engine)." (`option_tables.lua:486-490`) — same behaviour, two different strings; quote
      each exactly. Ten unknown steps instead of a refusal is a defect.

### Cataclysm Classic (40402) and Mists Classic (50500) — not supported clients
The build ships these two TOC flavours, but they deliberately omit
`LibClassicSwingTimerAPI`, so they load with the **inert stand-in** (the Retail shape).
- [ ] Load: **no Lua error**, the options UI, the HUD, the rotation label and design mode all
      work.
- [ ] The bars do **not** move, and the one-time notice "Swing timer bars are unavailable on
      this client; range and GCD features remain active." is shown (`main.lua:663`).
- [ ] The rotation scenario is refused (same two strings as Retail above).
- [ ] **A static bar here is not a defect** — record it and move on. Do not file a
      swing-timer bug against Cata/Mists.

### Still UNCONFIRMED in the 2026-10-20 wave
Every item below landed offline and was never observed in a client. Mark each CONFIRMED /
UNRESOLVED / STILL-UNCONFIRMED and write down what you actually saw. A row that must never
prompt is just as important to confirm as one that must.

- [ ] **Gladiator Stance (SoD, 412513)** — the row must **never** prompt: its APL gate is the
      SoD T1 damage **set bonus**, and the client can read the Forecast buff but not the set
      ownership. Confirm the guide never asks for the stance on SoD, and record whether the
      Forecast aura is readable at all.
- [ ] **Chain Lightning (shaman)** — the enemy-count sensor does not exist, so the row must
      **never** prompt. Confirm the guide never asks for Chain Lightning, and record what it
      does instead.
- [ ] **Hypersharp (WotLK rogue, 54758)** — "Hypersharp Weapon" does **not exist** in the WotLK
      client; 54758 is the belt enchant's *effect* ("Hyperspeed Acceleration"). The row is
      honestly off and its dead arm was removed: confirm the guide never prompts it.
- [ ] **Cat Form (druid)** — the arm is gated by a Feral-tree spec probe, the Cat Form aura and
      the form index. The clients this addon targets expose **no cat-vs-bear spec read**, so a
      Feral-tree bear tank out of bear form may still be told to shift: record it if you see it.
- [ ] **Bloodlust (TBC druid, 2825)** — 2825 is the **Shaman's** Bloodlust, a spell the druid
      cannot cast, and the APL's own "Bloodlust Time" variable has no addon counterpart. The
      row is honestly off: confirm the druid guide never asks for Bloodlust.
- [ ] **Frost Shock pick (TBC shaman)** — the APL's Shocks group picks **one** filler. The
      option `guide_filler_shock` (earth / frost, default `earth`) states the choice; with
      Frost Shock picked, the Frost Shock row must prompt and the Earth Shock filler must go
      quiet. Record what the default does and what the Frost pick does.
- [ ] **TBC twist ranks (shaman)** — the shipped row keeps 8512 (Windfury Totem rank 1, a
      deliberate downrank) and carries the APL's own TBC id 25587; the alternation's other half
      is the Grace of Air Totem 25359. Record which rank the twist icon shows on TBC.

## Step 2 — evidence to hand back

1. The `/st diag` lines from **every** client, verbatim (the login one-liner and the whole
   verbose block, including the **`ticks`** line and the `diag runtime …` counters line).
2. Every Lua error text (copy it out; "there was an error" is not evidence).
3. For each visual you enabled: pass / fail / did-not-see, with what you expected.
4. Anything that *looked* wrong but printed nothing — those are the silent-degradation cases this
   script exists to catch.
5. The client(s) you tested and the addon version.
6. The **Still UNCONFIRMED** list above, marked per item, plus the per-class utility-row and
   pre-pull results from the practice pass, the **design-mode element count** (13, or 14 on a
   druid), the **trinket gate** result (what a passive stat stick and an on-use trinket each
   showed) and the **warrior's W-21 Sunder mirror** result (was it off until you turned it on,
   did the HUD icon ride the GCD, did the guide's Sunder icon count the debuff down).

## What NOT to conclude from this pass

- "No errors" is not "working": a guide that cannot decide renders nothing (unknown-hides),
  and Retail hides swings by design.
- The 5s deadline disarming a library is a *fallback*, not a fix — report where you see `fallback`.
- An unknown read in a drill or a scenario step is **not** a wrong grade: it must record no
  attempt at all. If you see a guess, that is a defect, not a "client quirk".
- A **hold** is not an unknown: a step the class states as a hold is a decision — casting
  during it is an illegal cast (F) and doing nothing is correct (no attempt). Only a step with
  neither an action nor a hold records no attempt.
- Other players' addons can change globals this addon reads; if something behaves differently with
  another swing-timer addon loaded, say so explicitly.

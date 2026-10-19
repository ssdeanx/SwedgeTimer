# In-client test script

Purpose: turn one scarce test session into attributable evidence. Every failure mode in this
addon is silent (a library that never reports ready is disarmed by a 5-second deadline with a
single chat notice; nil-guards render nothing; four guides default OFF), so "it loaded fine" is
not a result. Write down what each client prints and what each visual does.

Supported clients under test:

| Client | Interface | Swing engine expectation |
| :--- | :--- | :--- |
| Classic Era / Season of Discovery | `11509` | vendored `LibClassicSwingTimerAPI` |
| TBC Anniversary | `20506` | vendored `LibClassicSwingTimerAPI` |
| WotLK Titanforge | `38002` | vendored `LibClassicSwingTimerAPI` |
| WoW Forever | `16001` | native `PLAYER_SWING` (`swing_source.lua`) |
| Retail / Live (Midnight) | `12.1.x (120100, 120105)` | inert stand-in (bars intentionally static) |

---

## Before the first launch

1. **Back up anything you care about**: copy `WTF/Account/<you>/SavedVariables/SwedgeTimerDB.lua`
   (and ideally the whole `WTF/` folder) plus the addon folder itself. The first login writes
   SavedVariables; nothing else can un-write that.
2. In game, run: `/console scriptErrors 1` — so any Lua error is visible instead of swallowed.
3. Know the version under test (top of `main.lua` / the TOC) and note it below.

## Step 0 — every client, every time (2 minutes)

1. Log in. Expect **no Lua error** and the bars on screen.
2. Run **`/st diag`**. Expected shape (values change per client):
   ```
   SwedgeTimer diag: family=WRATH iface=38002 version=2.1.0 engine=vendored-lib lrc=ready lcd=present ldb=pending guides=PALADIN:on WARRIOR:off DRUID:off SHAMAN:off HUNTER:off
   SwedgeTimer diag: flags stl_ready=true llm_ready=false lrc_ready=true lrc_unavailable=false deadline=no init=yes
   SwedgeTimer diag: modules practice=yes hud=yes rotation=yes design=yes providers=5/5
   SwedgeTimer diag: secrets api=no
   ```
   - `engine=` must match the table above for the client you are on.
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
- [ ] Paladin guide (enable in options): CS/Command/Blood/twist icon switches; HOLD/RIDE appears.
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
- [ ] Guides: enable warrior/druid/shaman/hunter one at a time and verify their prompt rules
      (see the class-specific criteria in the release notes).
- [ ] Practice: start a fight, make a twist, stop; enter combat mid-session → "paused", leave →
      resumes with timers shifted, no instant expiries; the panel reset button visibly
      re-anchors the panel; the timeline drags and persists, and its X button closes it.
- [ ] Design mode: `/st design` lists the practice rotation + timeline targets alongside
      the panel, and both drop where dragged.

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

## Step 2 — evidence to hand back

1. The `/st diag` lines from **every** client, verbatim.
2. Every Lua error text (copy it out; "there was an error" is not evidence).
3. For each visual you enabled: pass / fail / did-not-see, with what you expected.
4. Anything that *looked* wrong but printed nothing — those are the silent-degradation cases this
   script exists to catch.
5. The client(s) you tested and the addon version.

## What NOT to conclude from this pass

- "No errors" is not "working": the four new guides default OFF, and Retail hides swings by design.
- The 5s deadline disarming a library is a *fallback*, not a fix — report where you see `fallback`.
- Other players' addons can change globals this addon reads; if something behaves differently with
  another swing-timer addon loaded, say so explicitly.

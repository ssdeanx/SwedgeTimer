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
| Retail / Live (Midnight) | `120100` | inert stand-in (bars intentionally static) |

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
   SwedgeTimer diag: family=WRATH iface=38002 version=2.0.8 engine=vendored-lib lrc=ready lcd=present ldb=pending guides=PALADIN:on WARRIOR:off DRUID:off SHAMAN:off HUNTER:off
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
      "Successful TWIST!" and (if enabled) the sound cue arrives just *before* the band.
- [ ] Paladin guide (enable in options): CS/Command/Blood/twist icon switches; HOLD/RIDE appears.
- [ ] Seal swipe on the guide's Command/Blood icons reads ~30 s (LibClassicDurations).
- [ ] Shaman: weave marker shows; cast a Lightning Bolt that outlasts the swing — the spark must
      travel one way only (never jump back), and turn red when it would clip.
- [ ] Warrior: queue Heroic Strike with low rage → bar turns the insufficient-rage colour; Blood
      Surge proc → glow starts once and stops cleanly.
- [ ] Druid: Maul queue tint; form colours in cat/bear/travel; energy tick column in cat form.
- [ ] Hunter: auto-shot cycle syncs the ranged bar; queue Raptor Strike → yellow tint; the hunter
      cast bar shows the "Auto Shot" window label in the last ~0.5 s + latency.

### WotLK Titanforge (38002) — the full pass
Everything above, plus:
- [ ] Warrior: apply Rend/Sunder/Deep Wounds to a dummy → stacked bars above the mainhand bar;
      Sunder shows its stack count; Shield Block bar appears while buffed; casting Slam shows the
      "SLAM X.Xs" bar; get dodged → the Overpower flash ("OP") appears and clears when you cast it.
- [ ] Druid: Mangle/Rip/Rake bars count down with a glow in the last 4 s; refresh thresholds fire.
- [ ] Shaman: Windfury ICD strip (red → orange → green) after a swing; Flame Shock target bar;
      `SS`/`SR` badges; Lightning Shield charge row.
- [ ] Hunter: the 4-state range helper strip (melee/sweet spot/ranged/OOR), Rapid Fire bar, aspect
      icon; Steady/Aimed casts take over the cast bar from the Auto-Shot window.
- [ ] Cooldown HUD (enable): CS/Judgement/Consecration/Exorcism swipes, trinket cooldown/proc,
      Wings glow when ready, blue/red tints for no-mana / out-of-range.
- [ ] Rotation label (enable): shows `2/3`-style text; all four formats; drag + lock.
- [ ] Guides: enable warrior/druid/shaman/hunter one at a time and verify their prompt rules
      (see the class-specific criteria in the release notes).
- [ ] Practice: start a fight, make a twist, stop; enter combat mid-session → "paused", leave →
      resumes with timers shifted, no instant expiries.

### WoW Forever (16001)
- [ ] Bars move — driven by the native `PLAYER_SWING` events (no classic combat log).
- [ ] Paladin: the twist band shows (Mainline-code client, but the swing engine runs here);
      no twist *attempt/success* feedback (no combat log) — expected.
- [ ] Warrior: no Overpower flash (no combat log) — expected.
- [ ] Range: may work through the interact-distance checkers or fall back with a one-time notice —
      either is fine; record `lrc=` and whether range text ever fills.
- [ ] Shaman weave, hunter cast bar, druid trackers and the guides all behave as on WotLK.

### Retail / Live (120100)
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

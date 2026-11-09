# The druid's filed residuals: HU-14, the dead APL rows and the honest flags — 2026-10-20

Desk: `druid-apl` (resumed). **Supersedes nothing**: the utility-layer build is
`bench/druid_apl_utility_build_2026-10-20.md`; this file closes what it filed.

**Scope:** `classes/druid.lua`, `druid_guide.lua`, `tests/druid_state.lua`,
`tests/druid_guide_state.lua`. One new bench file. No git, no lint-config change, no
TOC / version / option / config change, no other class touched. The dispatch
(2026-10-20) assigns the Forever chain fix to this lane — the open question in
HU-14 ("who owns the Forever chain fix") is answered by that dispatch.

---

## 1. HU-14 — the FOREVER chain named a spell the client does not have

### 1.1 The defect, re-verified from the sources (fetched 2026-10-20)

The **Forever client has no Mangle spell at all**:

* `wowsims/forever sim/druid/spell_data_auto_gen.go` carries **no Mangle table**.
  Its ladders: `FaerieFire: spelldata.Ranked(770, 778, 9749, 9907)`,
  `LeaderOfThePack: spelldata.Ranked(17007)` — and no Mangle entry.
* `wowsims/forever sim/druid/` has **no per-ability Mangle file** (the directory
  listing: `mangle.go` is absent; `claw.go`, `shred.go`, `rip.go`, `rake.go`,
  `ferocious_bite.go` are present).
* `wowsims/forever sim/druid/druid.go:115` — `if druid.InForm(Cat|Bear) &&
  druid.Talents.LeaderOfThePack` — the Leader of the Pack is a **Feral Combat
  tree talent**, and `wowsims/forever sim/druid/talents.go` registers exactly
  three trees (Balance, Feral Combat, Restoration).
* The **Forever APL's own builders are 9830 Shred and 9850 Claw**
  (`wowsims/forever ui/specs/druid/feralcat/apls/default.apl.json`, the
  `Builders` group at **i=9**), and the APL carries **no Mangle row anywhere**
  (the full priorityList, re-fetched and expanded group by group: i=0 item
  10646 · i=1 768 Cat Form · i=2 the `Berserk` group · i=3 the `Cooldowns` group
  · i=4 9830 Shred · i=5 9850 Claw · i=6 the `Bleeds` group · i=7 22829
  Ferocious Bite · i=8 1322605 Shifting Power · i=9 the `Builders` group · i=10
  29166 Innervate · i=11 9907 Faerie Fire).

Consequence in game (the defect HU-14 describes): the class's Mangle ids are the
TBC ones (33983/33987), so `mangle_remaining` is **always nil** on the Forever
client, and the engine's F5 branch (`mangle_remaining nil -> "mangle"`) therefore
answered **"mangle" on every tick**, making the F6 (the Bite) and F7 (the builder)
branches unreachable.

### 1.2 The fix (what the APL's slot actually says)

The APL's slot where the Mangle row stood is **empty** — the APL's order around
there is `Bleeds (Rip, Rake) -> Bite -> Shifting Power -> Builders -> Innervate ->
Faerie Fire`. So the honest fix is to **delete the branch**, not to invent a
substitute spell:

* `druid_guide.lua` — the FOREVER chain's `F5` Mangle branch is **removed**; the
  chain now runs F2 (the Omen Shred) → F3 (Rip) → F4 (Rake) → F6a/F6b (the
  Bite) → F6c (the Faerie Fire fish) → F7 (the Shred builder) — **the APL's own
  order**, and the Bite and the builder are reachable again.
* `classes/druid.lua` — the rotation table's **FOREVER `mangle` row is removed**
  (it named a spell the client cannot cast). The FOREVER slice now carries the
  APL's own builder half: the utility spine's **Claw** row (RESERVED — its read
  does not exist yet), so the engine answers the APL's **Shred**.

The rule ids of the surviving branches are untouched (F6a/F6b, F6c, F7) and the
removal is written down in place, in the ERA-appendix style the file already
uses ("REMOVED (was E2, …)").

### 1.3 The same defect, one branch further: the FOREVER **bear** fallback

The bear chain's rule 3 fell back to `"mangle"` on every family that is not
runeless Era — including the Forever client. That is the same wrong action on the
same client, so it is closed with the same rule: `druid_client_has_mangle()`
(now a named helper in `druid_guide.lua`) returns false for runeless Era and for
the FOREVER client, and the bear chain **waits** (action nil, no hold) there.
SoD still rides rule 3 (it proves Mangle through its rune), and TBC / WotLK / Cata
/ Mists are unchanged.

**This is a behaviour change to a shipped bear chain on one client** and is
called out here on purpose: it is the same defect class as HU-14 and the rule
"never a wrong action on a client without the spell" outranks the scope of the
filed row.

---

## 2. The two dead APL rows reconciled

### 2.1 The Era APL's `[1]` row casts 13494 = "Haste"

Re-verified independently of the lane (2026-10-20):

* `wowsims/classic ui/feral_druid/apls/feral.apl.json` **i=1** casts **13494**
  under the condition `auraIsActive 768` (the cat form) + `spellIsKnown 13494` +
  `not auraIsActive 13494` + `currentTime < 90` — so the row is a **cat-form**
  row with a 90 s fight window (the shipped Leader of the Pack arm reads exactly
  that window: `LOP_FIGHT_WINDOW_ERA_SECONDS = 90`).
* The **1.15 client's own spell data** (classic.warcraftdb.com, fetched
  2026-10-20): **13494 = "Haste"** (in no druid skill line), **17007 = "Leader of
  the Pack"**, 17392 = "Faerie Fire (Feral)", 9896 = "Rip".
* The classic sim registers **no** spell 13494 (`sim/druid/
  spell_data_auto_gen.go` has no 13494 and no Mangle entry at all — Vanilla has
  no Mangle), and the sim's APL runner drops a row whose spell the actor does not
  have: `GetAPLSpell` walks the actor's own spellbook
  (`wowsims/tbc-new sim/core/apl_helpers.go:205-225`) and `newActionCastSpell`
  returns nil for a spell that is not in it (`sim/core/apl_actions_casting.go:
  16-19`), so the row is never created. The row is dead **in the sim and on the
  client**.

The line it means is the Leader of the Pack, and the table already carries the
**client's own id 17007** with the dead id cited in the row's `source`. This lane
**pins** that reconciliation (the id, the "dead as written" note) so it cannot
drift again.

### 2.2 The Era APL has no Rip row

The Era APL's rows are the Faerie Fire (17392), the dead 13494, the harness rows,
the Ferocious Bite (31018), the Shred (9830), the Claw (9850), the Faerie Fire
refresh (17392), the consumables, the Innervate (29166) and the Cat Form (768) —
**no Rip**. The table's Era Rip row (E1) is the **sim's own** rotation line
(`wowsims/classic sim/druid/feral/rotation.go`: `canRip`), and its `source` says
so. This lane pins both facts: the row carries the **client's** Rip r6 (9896)
and its source states that the Era APL has no Rip row.

### 2.3 What the FOREVER slice carries now

`FOREVER` = shifting_power (F1) · berserk (F1b) · shred (F2) · rip (F3) · rake
(F4) · bite (F6a/F6b) · faerie_fire (F6c) · shred (F7) + the utility spine's
cat_form, claw, innervate and elunes_light rows. **No Mangle anywhere** (pinned
twice: the slice and the whole table).

---

## 3. The Cat Form row: the arm, and the gate that makes it honest

The lane filed this row with `engine = false` because "the guide has no
feral-spec gate — an arm would nag every caster druid". **The gate exists**: it
is the class's own spec read.

**The spec probe (`inputs.feral_spec`)** — the family's Feral-tree talent, read
through `api.is_spell_known` (the class's own knowledge-level probe; `IsSpellKnown`
takes a spell id on every supported client — `classic_era`, `classic_anniversary`
and `forever` all forward to `C_SpellBook.IsSpellKnown(spellID)`):

| family | probe | why it is a Feral-tree talent |
|---|---|---|
| ERA (and the SoD, the same client) | **17392** Faerie Fire (Feral) | `wowsims/classic sim/druid/faerie_fire.go:26` — `druid.InForm(Cat\|Bear) && druid.Talents.FaerieFireFeral` gates the 17392 spell; the SoD sim's own `faerie_fire.go:41` does the same |
| TBC | **27011** Faerie Fire (Feral) r5 | `wowsims/tbc-new sim/druid/faerie_fire.go:49` — `if !druid.Talents.FaerieFireFeral { return }` |
| FOREVER | **17007** Leader of the Pack | `wowsims/forever sim/druid/druid.go:115` — `druid.Talents.LeaderOfThePack` in the Feral Combat tree |

A resto or a balance druid never has Feral-tree points, so the probe answers
false for them and the call never shows. The WotLK client has **no** probe
(`nil`): its APL carries no Cat Form row at all.

**The aura read (`inputs.cat_form_active`)** — the player's own aura walk (the
class's merged HELPFUL walk, one extra key: the Cat Form aura, id **768**,
matched by id first, then the localized name, then the literal English name).
Tri-state, exactly the Leader of the Pack read's shape: **true** = the aura is
up, **false** = the walk answered and the aura is absent, **nil** = the walk has
not answered yet (unknown, never a prompt).

**The rule** (`druid_guide.lua`'s `druid_cat_form_wanted`): all three proofs —
`feral_spec == true`, `cat_form_active == false`, and a form the cat rotation
uses but the other chains do not own (**0** = the humanoid form, **4** = the
travel form; the bear form belongs to the bear chain, the cat form is already
there, and the tree/moonkin (5) and flight (6) forms are not the cat
rotation's) — then **hold "CAT FORM"** (the hold-overlay convention, no guide
slot exists for the line).

**The APL order against the Innervate row** is honoured per family: the Cat Form
row sits **above** the Innervate on SoD (i=0 vs i=4) and on Forever (i=1 vs
i=10) and **below** it on Era (i=14 vs i=13) — so the two are ordered by the
family, never by a fixed rank.

**KNOWN LIMIT, stated in the row itself:** the clients this addon targets expose
no cat-vs-bear spec read (the talent trees are readable on WotLK only —
`main.lua`'s `talent_positions` table), so a Feral-tree **bear tank** out of the
bear form can still be told to shift. The guide's bear chain owns the bear form
itself (form 1), so the call can only show outside it. Filed as the row's
`gate` text, not hidden.

**Default-visible surface:** the arm adds one HOLD to the guide's own surface
(no widget, no option, no bar). The guide ships enabled
(`nextaction_enabled = true`), so a Feral-tree druid who is proven out of the cat
form now sees the call — the APL's own row, gated by the spec proof. No options
widget was added: `option_tables.lua` is out of this lane's scope, so a toggle
behind it (if the operator wants one) is the options pass's job.

---

## 4. The Bloodlust: the line cannot be evaluated, and the flags now say so

The TBC APL's **i=0** row casts **2825** when the fight time reaches the APL's
`Bloodlust Time` **variable** (the shipped value is **5 s** — re-fetched from
`wowsims/tbc-new ui/specs/druid/feralcat/apls/default.apl.json`, whose
`valueVariables` list opens with `Bloodlust Time = {"const": {"val": "5s"}}`).

**The deeper finding, and it is the same shape as the Era's dead 13494 row:**
**2825 is the Shaman's Bloodlust, not a druid spell.**
`wowsims/tbc-new sim/shaman/bloodlust.go:11` is the Bloodlust; the TBC **druid**
sim has no Bloodlust at all (no `sim/druid/bloodlust.go`, no 2825 in
`sim/druid/spell_data_auto_gen.go`). The APL runner drops a row whose spell the
actor does not have (`GetAPLSpell` walks the actor's own spellbook —
`sim/core/apl_helpers.go:205-225` — and `newActionCastSpell` returns nil for a
spell that is not in it, `sim/core/apl_actions_casting.go:16-19`), so the row is
dead **for a druid**: no arm could ever be honest here — it would ask a druid
to cast a spell the druid does not have. (The TBC sim's Feral tree does carry
the Leader of the Pack — `wowsims/tbc-new sim/druid/feralcat/feralcat.go:77`,
`cat.Talents.LeaderOfThePack` — so the row's *intent* is a raid buff, not a
druid ability.)

The addon cannot know the raid's plan either: the `Bloodlust Time` variable is a
sim user setting with **no addon counterpart** (no option — `option_tables.lua`
is out of scope — and no way to read the raid's intent; the practice panel's own
Bloodlust button is the manual path).

**So the honest flags are `live = false, engine = false`**, with the `needs`
text naming both obstacles (the spell the druid cannot cast, and the variable
with no counterpart). The lane's earlier `live = true` said "the read exists" —
true, but the read reads a spell the druid can never cast, and the bench's own
definition of `live` is "the line's read exists **and the line can be evaluated
from it**". The table's shape comment now states that definition in full.

---

## 5. The Claw row: RESERVED, and the flags tell the truth

The Claw stays **RESERVED**: the read that decides "the Shred cannot land" does
not exist (`can_shred` is RESERVED — the sim's `CannotShredTarget` has no WoW API
counterpart; `api.IsSpellUsable` answers usability, never facing), so
`live = false` and `engine = false` both stand. The `needs` text now also says
what the row **is** after HU-14: the APL's own builder half (the Forever APL's
i=5 and i=9), while the engine's Forever chain answers the APL's **Shred** in
that slot.

---

## 6. Validation

* `tests/druid_state.lua` — **PASS (1205 checks)**; +22 pins: the form upkeep's
  class-side reads (the three families' spec probes, the WotLK "no probe", the
  Cat Form aura's tri-state), the Cat Form row's new flags and its `gate` text,
  the Bloodlust row's two flags, the Claw row's two flags, the FOREVER slice's
  "no Mangle" (twice), the ERA reconciliation (the Rip row's id and its
  "the Era APL has NO Rip row" note, the Leader of the Pack row's client id and
  its "dead as written" note).
* `tests/druid_guide_state.lua` — **PASS (95910 checks)**; the new pins: the
  FOREVER chain never answers a Mangle (the HU-14 pins plus a 162-combination
  Mangle sweep that walks the debuff independently of the Rip and the Rake), the
  FOREVER bear chain waits where Wrath Mangles (and shares the Maul/RIDE outcome
  otherwise — the parity sweep gained three pins per combination), the Cat Form
  arm (the three proofs, the six forms, the four families, the APL order against
  the Innervate) and the class-side gather reads.
* **luacheck** on the four touched files — **0 warnings / 0 errors**. The tree's
  floor is untouched: the full run reports **2 warnings / 0 errors** (both
  pre-existing, in untouched files — `compat.lua` and `main.lua`).
* **15/15 mutations killed** on `/tmp/opencode` copies
  (`python3 /tmp/opencode/druid-residuals/mutations_druid_residuals.py`
  reproduces them) — among them the required **"a wrong action on a client
  without the spell"** mutant (M1: the FOREVER Mangle branch comes back → the
  FOREVER Mangle sweep and the HU-14 pins fail) and its bear twin (M2), the
  Cat Form arm's three gates (M3 the spec gate, M4 the aura gate, M5 the form
  gate, M6 the family gate, M7 the APL order), the class-side read mutants (M8
  the wrong probe spell, M9 an aura read that answers without the walk) and the
  flag mutants (M10 the FOREVER Mangle row comes back, M11 the Cat Form row
  claims no arm, M12 the Bloodlust row claims it can be evaluated, M13 the Claw
  row claims the read exists) and the id mutants (M14 the Era Rip id, M15 the
  Leader of the Pack id).
* The full harness: **41 steps, 0 failed**. (Mid-lane the tree showed the
  concurrent rogue lane's in-flight state — `classes/rogue.lua` mid-write, then
  two rogue option pins; both cleared on the final run. No failure in this
  lane's files at any point.)
* **Verified offline** — no client run happened here, so every behaviour claim
  above is a simulation claim, not an in-client one.

---

## 7. Filed follow-ups (not fixed here)

1. **The SoD Mangle rune.** The SOD chain's S6 branch
   (`mangle_remaining nil -> "mangle"`) fires whenever the Mangle debuff is
   absent — and the class's Mangle ids are TBC's, so a SoD player **without** the
   Mangle rune (but with the Savage Roar rune, so `sod_runes_present()` is true)
   would be prompted a spell they do not have. The same class of defect as HU-14,
   on a family HU-14 does not cover. The honest fix needs a rune-knowledge probe
   for the Mangle rune itself (`api.is_spell_known(409828)` is the candidate) —
   filed, not built here (out of the dispatch's scope).
2. **The cat-vs-bear spec read** (the bear-tank limit in §3) — the clients this
   addon targets expose no talent read outside WotLK, so the arm cannot separate
   a Feral-tree bear tank from a Feral-tree cat DPS. Filed in the row's `gate`
   text.
3. **The Bloodlust option** (the `Bloodlust Time` counterpart) — needs the
   options pass (`option_tables.lua`) and a decision on whether the addon should
   ever call a raid cooldown.

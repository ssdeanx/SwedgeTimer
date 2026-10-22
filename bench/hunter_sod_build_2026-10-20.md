# The hunter's HUD slots, per BUILD (Era-base vs SoD on the Era client) — 2026-10-20

Desk: `hunter-sod-build`. **Closes the residual filed in
`bench/hunter_hud_family_2026-10-20.md` §7.2** ("the SoD client HAS the Bestial
Wrath, but the ERA family pick drops that slot for SoD too") and §7.4 ("the Mists
client's Raptor rank is CLIENT-UNCONFIRMED").

**Scope:** `classes/hunter.lua`, `hunter_guide.lua` (the frozen-spec display-slot
block only), `tests/hunter_state.lua`, `tests/hunter_guide_state.lua`,
`tests/hud_state.lua` (**the hunter census only**). No git commits, no lint
config, no other class, no docs/TOC/version, no `practice*.lua`,
`option_tables.lua`, `config_presets.lua`, `main.lua`, `diag.lua`, `compat.lua`,
`hud.lua`, `bars.lua`, `guide_contract.lua`, `run.sh`.

---

## 0. Correction (2026-10-20, orchestrator-verified)

The claim that "the corpus' `wowsims` citations are currently unverifiable" is **a probe error, not a
fact**: the lane fetched `github.com/wago-io/wowsims` — the wrong org. The real path resolves and the
cited content matches:

- `https://raw.githubusercontent.com/wowsims/classic/master/sim/core/rage.go` → **HTTP 200** (verified
  by the orchestrator, 2026-10-20). Its content confirms the warrior lane's numbers exactly:
  `MaxRage = 100.0`, `generatedRage := damage * 7.5 / rageConversion` (white hits),
  `damage * 2.5 / rageConversionDamageTaken` (damage taken), and `GetRageConversion`: level 25 →
  **82.25**, level 40 → **140.5** ("Tested" in the source).
- The corpus citations are therefore **valid**. The two ids the lane refuted (the Cata Raptor 2973 vs
  48996, the Mists Raptor) were refuted **against the clients' own spell tables** (the operator's
  1.15.9 `wow.export` dump and warcraftdb's per-expansion domains) — that part of the finding stands,
  and client data is the stronger evidence.

**Rule for future lanes:** the wowsims org is `wowsims` (`wowsims/classic`, `wowsims/sod`,
`wowsims/tbc-new`, `wowsims/forever`, `wowsims/wotlk`); a 404 on `wago-io/wowsims` proves nothing.
The client data (`/home/sam/wow.export` = the 1.15.9 SoD client) and warcraftdb's per-expansion
domains remain the strongest available id evidence.

## 0. Summary

| | before | after |
|---|---|---|
| the HUD's dead-slot filter | one pick per **family** (the ERA pick dropped the Bestial Wrath for SoD too) | one pick per **family AND build** — the SoD build of the Era client keeps the slot |
| the SoD Bestial Wrath id | none (the slot was gone) | **19574** — the 1.15.9 client's own rank, from the shared owner table |
| the guide's SoD slot set | 12 slots (no Bestial Wrath) | **13** slots (the Bestial Wrath the SoD client has) |
| the guide/HUD agreement on SoD | n/a (neither carried it) | the same slot, the same id, from **one** decision |
| the Mists Raptor slot | shipped the id 48996 — a spell the Mists client does **not** have | **dropped** (the client's own Raptor Strike id is unknown; an id is never guessed) |
| the Cata Raptor slot | shipped 48996 (the retail Cata rank) | **2973** — the Cata CLASSIC client's own rank |
| the HUD's per-family slot COUNT | ERA 6 · TBC 9 · WRATH 9 · FOREVER 7 · CATA 9 · MISTS 9 · RETAIL 9 | ERA **6 (base) / 7 (SoD)** · TBC 9 · WRATH 9 · FOREVER 7 · CATA 9 · MISTS **8** · RETAIL 9 |

**Everything below is verified OFFLINE only.** The in-client behaviour is
UNCONFIRMED: the operator's session is the only thing that can confirm it.

---

## 1. The client's truth (fetched 2026-10-20)

### 1.1 LOCAL — the operator's own Classic 1.15.9 client dump

`/home/sam/wow.export` (the operator's CSV export of the 1.15.9 client) **is the
SoD client**: it carries the SoD-only runes and nothing else does.

| id | in the 1.15.9 client's spell table? | what the table says |
|---|---|---|
| 409433 (Chimera Shot) | **present** | the SoD gloves rune — the class's own SoD detector |
| 437123 (the SoD Steady Shot rune) | **present** | the SoD Steady Shot (NOT 56641) |
| 458482 (Wyvern Strike) | **present** | the SoD rune |
| 409593 (the SoD Kill Shot) | **present** | the SoD execute |
| **19574 (Bestial Wrath)** | **present** | `Spell.csv:7657` — "Send your pet into a rage causing $s2% additional damage…" |
| 19574's skill line | `SkillLineAbility.csv:3723` | skill line **50 = Beast Mastery** (`SkillLine.csv`) → the Bestial Wrath is a **Beast Mastery ability** on this client |
| 56641 (the TBC Steady Shot) | **absent** | the 1.15.9 client has no Steady Shot at all |
| 34026 (Kill Command) | **absent** | the 1.15.9 client has no Kill Command |
| 2973 / 14266 / 25294 / 20904 / 3045 | present | the Era ranks the table cites (Raptor / Multi / Aimed / Rapid Fire) |

**So the SoD client HAS the Bestial Wrath (19574)** — the brief's premise, now
sourced from the client's own spell data rather than from a sim repository.

### 1.2 WEB — warcraftdb's per-expansion domains ARE each client's own spell table

Each expansion domain answers only the ids that client carries, and a miss is a
"**Not Found - Warcraft DB**" page. That is the same evidence shape the corpus's
H4 used for the Steady Shot (a version page exists ⇔ the client carries the
spell), on the client's own data rather than on a guide page.

| id | classic (1.15) | tbc (2.5.6) | wotlk (3.3.5) | cata (4.3.4) | mop (5.5) | forever (1.60) | retail (12.1) |
|---|---|---|---|---|---|---|---|
| 2973 Raptor Strike | **page** | – | – | **page** | **Not Found** | – | – |
| 14266 Raptor Strike | – | – | – | – | **Not Found** | **page** | – |
| 27014 Raptor Strike | – | **page** | – | – | **Not Found** | – | – |
| 48996 Raptor Strike | – | – | **page** | **Not Found** | **Not Found** | – | – |
| 186270 Raptor Strike | – | – | – | – | – | – | **page** |
| 2643 Multi-Shot | page | page | – | page | page | page | page |
| 19434 Aimed Shot | page | page | – | page | page | page | page |
| 3045 Rapid Fire | page | page | page | page | page | page | – |
| 56641 Steady Shot | – | page | page | page | page | – | page |
| 19574 Bestial Wrath | page | page | page | page | page | page | page |
| 34026 Kill Command | – | page | page | page | page | – | page |

### 1.3 The corpus' source repo is GONE

`github.com/wago-io/wowsims` → **404** (the page and the API), for every branch
(`sod`, `cata`, `tbc-new`, `wotlk`, `classic`, `forever`, `mists`). The previous
lane's citations (`wowsims/classic sim/hunter/raptor_strike.go:11` and friends)
**could not be re-verified** on 2026-10-20 — the files are unreachable. This
lane re-sourced every cell it touched from the client's own data (§1.1, §1.2).

**Two of the previous lane's citations are refuted by the client's own data:**

* the **Cata** cell (48996, cited from `wowsims/cata`) — the Cata CLASSIC client
  (the client this addon targets: interface 40402) has **2973**; the retail Cata
  rank 48996 is not in that client's table at all. `wowsims/cata` is the RETAIL
  Cataclysm sim, not the Cata Classic client.
* the **Mists** cell (48996, CLIENT-UNCONFIRMED) — the Mists client's own table
  carries **no Raptor Strike** among every rank this tree knows (2973,
  14260..14266, 27014, 48995, 48996 all "Not Found"), so the shipped id pointed
  at a spell that client cannot have.

---

## 2. What changed

### 2.1 The build-aware dead-slot pick (`classes/hunter.lua`, `HUD_DEAD_SLOTS`)

The pick is no longer a static per-family table. The **ERA family carries a
BUILD dimension** — the same 1.15.9 client runs the Era-base game AND the SoD
game, and the two games do not carry the same spells:

* at load the ERA family keeps the Bestial Wrath **with no id** (an id-less slot
  is never offered, so it is never a dead cell);
* the **build is decided once, at post_init**, by the class's OWN SoD probe
  (`api.is_spell_known(409433)` — the Chimera Shot rune is SoD-only, so
  knowledge of it IS the detector). No new client read was added;
* the **SoD build** gives the slot the SoD id; the **Era-base build** drops it.

The pick for the other families is unchanged, plus one new entry: **MISTS drops
the Raptor Strike** (the client's own Raptor id is unknown — §1.2).

### 2.2 ONE decision, TWO surfaces (`classes/hunter.lua`, `resolve_guide_icons`)

The build decision is the same block that swaps the guide's slot set, and it now
drives the HUD's slot as well:

* the guide's **Era-SoD set** gains the Bestial Wrath (13 slots);
* the HUD's Bestial Wrath slot gets the same id on the same decision;
* the guide's slot id and the HUD slot id come from **one** value
  (`bestial_wrath_current_id or SPELL_ID_BY_FAMILY.bestial_wrath.SOD`).

So the two surfaces cannot disagree about which spells the running build has —
the failure the residual was about.

### 2.3 The id comes from the shared owner (`SPELL_ID_BY_FAMILY`)

`SPELL_ID_BY_FAMILY.bestial_wrath` gains a **BUILD-keyed** cell, `SOD = 19574`
(next to the family's cells). The table's header now states the rule: a BUILD
cell is read only when the class's own SoD probe says the SoD build is running.
The ERA cell stays EMPTY — the Era-base game never uses the 2.1 talent.

The runtime re-point (`:2212`) is untouched: the SoD Bestial Wrath slot is
re-pointed at the client's own rank exactly like every other slot.

### 2.4 The Mists and Cata Raptor cells

* `raptor.CATA`: **48996 → 2973** (the Cata CLASSIC client's own rank — §1.2).
* `raptor.MISTS`: the cell is **removed** and the reason is recorded in the
  table's comment; the HUD's pick drops the slot and the guide's **Mists set**
  (new, five slots) does not declare it. **No id was guessed.**
* The guide's Mists set is a new sibling of the base set; the base set (Cata,
  Mists, Retail) is unchanged for the families that have a Raptor rank.

### 2.5 The gather spends one more read on the SoD build

`inputs.bw_remaining_cd` reads the Bestial Wrath cooldown whenever the guide's
Bestial Wrath slot carries an id. On the SoD build it now does (the client HAS
the spell) → the SoD gather spends **6** cooldown reads instead of 5, exactly
like the other families that carry that slot (Forever, Cata, Mists, Retail). The
prompt itself stays TBC-gated (`bw_known`), so the engine's behaviour on SoD is
unchanged.

---

## 3. The pins

| pin | file |
|---|---|
| the HUD slot set per **BUILD** (Era-base 6 · SoD 7) | `tests/hunter_state.lua` (H-HUD-1, H-HUD-3), `tests/hud_state.lua` (§13b, §13g) |
| the effective id per build (SoD Bestial Wrath = 19574) | `tests/hunter_state.lua`, `tests/hud_state.lua` (§13g) |
| the guide and the HUD agree (same slot, same id, on SoD) | `tests/hunter_state.lua` (H-HUD-1), `tests/hud_state.lua` (§13g) |
| the per-family slot COUNT (MISTS 9 → 8; CATA unchanged at 9) | `tests/hunter_state.lua` (H-HUD-3), `tests/hud_state.lua` (§13f) |
| a client that cannot have a spell shows no slot for it | `tests/hunter_state.lua` (H-HUD-3 dead rows), `tests/hud_state.lua` (§13f) |
| the guide's SoD slot set (13 slots, the Bestial Wrath among them) | `tests/hunter_state.lua`, `tests/hunter_guide_state.lua` |
| the Mists table carries **no** Raptor id (an id is never guessed) | `tests/hunter_state.lua` (a source pin) |

The HUD census in `tests/hud_state.lua` measures the **shipped** state: the pick
is decided at post_init, so the Era/SoD censuses are taken after that decision.
The fixture grew ONE option, `opts.known_spells` (REPLACES the shared spellbook
table; the default path is byte-identical) — the other classes' censuses are
untouched.

---

## 4. Mutation proofs — 10/10 killed (`/tmp/opencode/huntersod_mutations.py`)

Baseline green; each mutant applied to a disposable copy of the tree under
`/tmp/opencode/huntersod-mut` and the three hunter suites run there.

| # | mutant | killed by |
|---|---|---|
| M1 | **the SoD build drops a slot it has** (the Bestial Wrath is dropped there too) | the SoD count/key pins (both suites) |
| M2 | the Era-base build keeps the Bestial Wrath | the Era-base count + "no Bestial Wrath slot ships" (both suites) |
| M3 | the SoD slot carries a wrong id (19575) | the SoD id pins (hunter + guide) |
| M4 | the guide's SoD set drops the Bestial Wrath (the surfaces disagree) | the guide/HUD agreement pins (all three suites) |
| M5 | the Mists table carries a guessed Raptor id again (48996) | the "no Mists Raptor rank" source pin |
| M6 | the Cata Raptor slot is back to the retail Cata rank (48996) | the Cata census pins (both suites) |
| M7 | the HUD's pick drops the Bestial Wrath at load (the build-blind pick) | the SoD count/key pins (both suites) |
| M8 | the SoD probe never fires (the build decision is never taken) | the SoD guide/HUD pins (all three suites) |
| M9 | the guide's Mists set keeps the Raptor Strike (a dead slot declared) | the "no dead slot is declared" pin |
| M10 | the HUD's Mists pick keeps the Raptor Strike (a dead cell ships) | the Mists count + "no raptor slot ships" (both suites) |

**The brief's requirement — a "SoD build drops a slot it has" mutant must fail a
pin — is met (M1).**

---

## 5. Validation

* `bash tests/run.sh` → **43 steps, 0 failed** (the floor).
* `luacheck .` → **2 warnings / 0 errors in 85 files** (the standing floor; both
  warnings pre-existing in `compat.lua` and `main.lua`, files this lane never
  touched). The lane's own five files: **0 / 0**.
* `tests/hunter_state.lua` → PASS (1506 checks) · `tests/hunter_guide_state.lua`
  → PASS (1962) · `tests/hud_state.lua` → PASS (817).
* Line endings preserved: `classes/hunter.lua` and `hunter_guide.lua` are CRLF
  (0 bare LF); the three test files are LF, as they were.
* **Upvalue headroom:** `classes/hunter.lua`'s `resolve_guide_icons` now has
  **59** upvalues (Lua 5.1's limit is 60 — the file was already at 58). It
  compiles; the next lane that adds a chunk-level local to that function must
  watch the ceiling.
* No git commands beyond one read-only `git diff --stat` for review. **The
  working tree carries every lane's uncommitted work** (82 files), so the diff
  is not a scope check for this lane; the scope check is the file list: this
  lane touched exactly `classes/hunter.lua`, `hunter_guide.lua`,
  `tests/hunter_state.lua`, `tests/hunter_guide_state.lua`, `tests/hud_state.lua`
  — and inside `tests/hud_state.lua` only the hunter census blocks (§13b, §13f,
  the new §13g), the `HUNTER_SPELLS` table and the one fixture option.

---

## 6. Findings that refine the brief's premise (READ THIS)

1. **The Era-BASE client HAS the Bestial Wrath too.** The brief (and the previous
   lane) say the Era-base pick is "correct … the spell does not exist there".
   The 1.15.9 client's own spell data carries 19574 as a **Beast Mastery
   ability** (§1.1) — and the Era-base game runs on that same client. So the
   Era-base drop is a **rotation decision** (the Era APL never casts the 2.1
   talent), not a client-capability fact. The brief pins the Era-base row to
   keep dropping the slot ("no default-visible change beyond the SoD
   correction"), and **that is what ships** — but an Era-base BM hunter who
   learned Bestial Wrath gets no HUD icon for it. That is the same shape of gap
   the SoD build had. **It is filed as a follow-up below, not built here.**
2. **The Cata Raptor cell was wrong** (§1.2) and is corrected to the Cata
   CLASSIC client's own rank. The effective id on that client was already 2973
   at runtime (the re-point resolves the client's own rank), so this is the
   declared-fallback correction, not a visible change.
3. **The Mists Raptor rank could not be sourced.** The Mists client's own table
   carries no Raptor Strike among every rank this tree knows, and the id is
   never guessed → the slot is filtered for that family and the reason is
   recorded in the table, in the pick's comment and in the guide's Mists set.
   It needs an in-client `GetSpellInfo` sweep or a Mists spell dump to close.
4. **The corpus' sim repo is unreachable** (§1.3). Every bench citation that
   points at a `wowsims/...` path is currently unverifiable; this lane used the
   clients' own data instead. The corpus needs a re-point at sources that still
   answer (warcraftdb's per-expansion domains, the operator's local
   `wow.export` dump).

---

## 7. Residuals filed (NOT built here)

1. **The Era-BASE Bestial Wrath** — the client has the spell; the Era-base pick
   drops the slot because the Era APL never casts it. Adding it would be a
   default-visible change on the Era client → **the operator rules** (this
   wave's brief pinned it as "no change").
2. **The Mists Raptor Strike id** — unknown; the slot is filtered there. The
   observation that closes it: the id on the 5.5.0 client (`GetSpellInfo` by
   name, or a Mists spell dump).
3. **The Era Steady Shot existence** (the steady lane's residual #2, still open)
   — untouched here: the ERA family's Steady probe is unchanged.
4. **The guide's non-HUD slots keep their own fallbacks** (the previous lane's
   residual #3) — untouched: those keys have no HUD counterpart.
5. **The Mists Rapid Fire** — the Mists client's table carries 3045 *and* the
   newer 36828; the shipped cell (3045) resolves and is not a dead slot, so it
   was left alone — but the "client's own rank" reading would say 36828.
6. **CHANGELOG.md / TESTING.md were not touched** (docs are out of this lane's
   scope).
7. **The corpus' `wowsims` citations** (§1.3) need a re-point — a corpus task,
   not this lane's.

---

## 8. The operator's in-client checklist (the one thing offline cannot prove)

| client | what to read |
|---|---|
| 1.15.9 (Era-base) | **six** slots: Raptor Strike, Multi-Shot, Rapid Fire, Aimed Shot + the two trinkets — every icon resolved (not blank), and NO Bestial Wrath cell |
| 1.15.9 (SoD) | **seven** slots — the same six **plus the Bestial Wrath**, and its icon is the 19574 texture (not a blank cell). The guide's row shows the same slot with the same icon |
| 1.15.9 (SoD) | `GetSpellInfo(19574)` answers (the Bestial Wrath) and `GetSpellInfo(409433)` answers (the Chimera Shot rune) — the two ids this lane's build decision reads |
| 2.5.6 (TBC) | nine slots, every icon resolved (unchanged) |
| 3.80.2 (Wrath) | nine slots (unchanged) |
| 1.60.1 (Forever) | seven slots (unchanged) |
| 4.3.4 (Cata) | nine slots; the Raptor Strike icon is the **2973** texture (the retail Cata 48996 is not on that client) |
| 5.5.0 (Mists) | **eight** slots — no Raptor Strike cell (its id is unknown); every other icon resolved |
| 12.1.x (Retail) | nine slots (unchanged) |

# The hunter's Steady Shot, per family — 2026-10-20

Desk: `hunter-steady-family`. **Release-gate blocker B2** (the test-sufficiency
audit): the hunter's **HUD** Steady Shot id was family-blind and asserted nowhere,
and the **Forever guide** slot set certified a Steady Shot row the corpus says the
Forever client cannot have.

Scope of the change (and only this): `classes/hunter.lua`, `hunter_guide.lua` (the
frozen-spec header), `tests/hunter_state.lua`, `tests/hunter_guide_state.lua`,
`tests/hud_state.lua` (the hunter census only). No git, no lint config, no other
class, no docs/TOC/version.

---

## 1. What the audit found (the two escapes)

| # | escape | evidence |
|---|---|---|
| (a) | The HUD's Steady slot carried ONE id (56641) for every family but Era. 56641 is the vanilla rank: it does not exist on the TBC client, so on TBC the slot resolved to nothing (no name → no cooldown/mana/range read; no icon texture). The suite pinned the HUD **key set** per family and never a slot's `spell` id, so it stayed green. | `classes/hunter.lua` (HUD slot set, before this change); `bench/rogue_hunter_eratbc_2026-10-19.md` §5 **H-HUD-2** (filed, then settled by the corpus correction); `bench/rotation_gap_vs_apl_2026-10-20.md` §0.0 **H3** (56641 does not exist on the TBC client; the TBC APL casts 34120 r1) |
| (b) | The Forever guide slot set still carried `guide_slot_steady`, and the pin certified a 12-slot set whose `steady` slot resolved to 34120 — a state the changelog says was corrected (the Forever client has no Steady Shot at all). The fixture even handed the Forever sandbox a Steady Shot the real client does not have. | `classes/hunter.lua` (`guide_slots_forever`); `tests/hunter_guide_state.lua` (the Forever block, before this change); `bench/rotation_gap_vs_apl_2026-10-20.md` §0.0 **H4**; `bench/hunter_utility_live_2026-10-20.md` §1 ("the Forever Steady Shot row is GONE"); `CHANGELOG.md` §[2.1.1] ("the **Forever client has no Steady Shot at all** — its row was removed") |

## 2. What changed

### 2.1 One owner for the Steady id (`classes/hunter.lua:103`)

`steady_id_by_family` is the single table behind **both** surfaces (the guide slot
and the HUD slot), so the two can never disagree:

| family | id | evidence |
|---|---|---|
| ERA | 56641 | the vanilla rank. The Era guide set and the HUD's Era pick DROP the Steady slot, so no Steady prompt fires on Era; the id stays because the gather's RANGE probe reads it — the shipped Era behaviour, kept exactly as it is. |
| TBC | **34120** | the TBC rank the APL casts — `bench/ids_research_2026-10-19.md` §2 ("34120 | Steady Shot (TBC rank)", wowhead TBC); `bench/rotation_gap_vs_apl_2026-10-20.md` §0.0 H3 |
| WRATH | **49052** | the WotLK rank the APLs cast — `bench/ids_research_2026-10-19.md` §2 ("49052 | Steady Shot", wowhead WotLK, scrape OK) |
| CATA / MISTS / RETAIL | 49052 | the same 3.x Steady Shot line. **CLIENT-UNCONFIRMED** on those three (no cited client read); the client's own rank replaces the fallback at post_init |
| FOREVER | *(no entry)* | the client has NO Steady Shot at all — §0.0 H4 (the spell arrived in 2.3, the Forever spell data carries no `SteadyShot` table) |

The guide slot (`classes/hunter.lua:1951`) and the HUD slot
(`classes/hunter.lua:2844-2845`) both read that table now. The guide slot's fallback
was `56641` for every family before — the same family-blind id.

### 2.2 The HUD re-points at the client's own rank (`classes/hunter.lua:2097`)

`resolve_guide_icons` re-points the HUD's Steady slot at the resolved rank
(`classes/hunter.lua:2097-2106`), the same pattern the Aimed Shot slot already
used (`classes/hunter.lua:2082-2086`). The rank comes from the SAME cached
resolver as the guide (`api.get_family_spell_id_state`), so the HUD and the guide
can never disagree about which Steady Shot the client has.

### 2.3 The Forever dead-slot filter (`classes/hunter.lua:2860`)

One table, one rule — a slot for a spell the running client does not have never ships:

* `ERA` → Steady Shot / Kill Command / Bestial Wrath (the shipped H-HUD-1 pick; SoD
  shares the ERA token, so it covers both);
* `FOREVER` → **Steady Shot** (the client has no Steady Shot at all — §0.0 H4).

The HUD on the Forever client therefore ships eight slots, not nine.

### 2.4 The Forever guide set drops the row (`classes/hunter.lua:2042`)

`guide_slots_forever` no longer declares `guide_slot_steady` (twelve → eleven
slots). The rule the Era set already follows ("dropped rather than shipped dark")
now covers the Forever client too. The guide's frozen spec in `hunter_guide.lua`
(the display-slot block) was re-cut to match: the Forever set names no Steady
Shot, and the base/Wrath rows carry the family's own rank instead of 56641.

### 2.5 No Steady probe on a client with no Steady Shot (`classes/hunter.lua:2437`)

The gather's Steady cast-time probe is now nil-guarded, and the Forever family
entry left `ST.HUNTER.CAST_TIME_FALLBACK.steady` (`classes/hunter.lua:1423`): a
family that never consumes the shot reads nil (the table's own doctrine, and the
rule the guide's `get_guide_cooldown(nil)` already followed). Effect: the Forever
client spends **no** Steady cooldown read and **no** Steady `GetSpellInfo` probe per
tick (before: a per-frame `GetSpellInfo(56641)` for a spell it cannot have).

### 2.6 The HU-13 flag sweep, strict (the operator's addition)

`tests/hunter_state.lua:4549` and `tests/hunter_guide_state.lua:3466` asserted
`entry.engine ~= false` — a TRUTHINESS test that passes for `nil`, `0` and any
truthy string. The sweep is now strict:

* `type(entry.live) == "boolean"` and `type(entry.engine) == "boolean"` on EVERY row;
* a `live == false` row names a non-empty `needs` (the cross-row rule the other
  five classes enforce) — the hunter's own extra check (the `needs` text names a
  real `api.*` wrapper in `compat.lua`) is kept.

The strict sweep found a real hole: **46 of the 47 hunter rotation rows declared
no `engine` flag at all** (only the filed FOREVER Aimed row declared one), and the
truthiness test passed them as "engine-facing". The data now declares the flag on
every row (`engine = true` on the 46 armed rows, `engine = false` on the filed
one) — the house convention the other five classes already follow
(`classes/druid.lua` declares both flags on every row). The production filters
(`entry.engine ~= false`) are unchanged and behave identically for the now
explicit data; the other five classes use the same production pattern, so the
hunter was not made an exception.

## 3. The pins

| pin | file:line |
|---|---|
| the HUD's Steady slot carries the TBC rank 34120 (and never 56641) | `tests/hunter_state.lua:2586` (the H-HUD-2 block), `tests/hud_state.lua:1555` |
| the Wrath HUD slot carries 49052 and the client's own rank re-points it | `tests/hunter_state.lua:2586` |
| the Forever HUD slot is ABSENT and the eight live slots ship in guide order | `tests/hunter_state.lua:2586`, `tests/hud_state.lua:1716` (the Forever HUD census: eight slots, eight icons, the row sized to six shown slots) |
| the Era HUD slot is still absent (unchanged) | `tests/hunter_state.lua:2586` |
| the HUD's Steady rank resolves BY NAME on TBC and never by name on Era | `tests/hunter_state.lua:2586` |
| the Forever guide declares ELEVEN slots and NO Steady slot; the frame holds 11 icons (25 frames) | `tests/hunter_guide_state.lua:2824` |
| the Forever gather: `steady_known` false, no Steady cast-time fallback, four cooldown reads (no Steady probe) | `tests/hunter_guide_state.lua:2824` |
| the Forever engine never emits a Steady action and no Forever slot lights | `tests/hunter_guide_state.lua:2824` |
| the HU-13 strict sweep (both files) | `tests/hunter_state.lua:4549`, `tests/hunter_guide_state.lua:3466` |

The fixture change that came with the correction: `tests/hud_state.lua`'s spell
table carries **34120** (the TBC Steady Shot) instead of 56641 — the TBC client
does not have 56641 (§0.0 H3). The Forever guide fixture no longer hands the
sandbox a Steady Shot at all (the client has none).

## 4. Mutation proofs (8/8 killed, on `/tmp/opencode` copies)

| # | mutant | killed by |
|---|---|---|
| 1 | the HUD's Steady slot back to the family-blind 56641 | `tests/hunter_state.lua` (3 checks), `tests/hud_state.lua` (2 checks) |
| 2 | the Forever guide's Steady row restored | `tests/hunter_guide_state.lua` (8 checks) |
| 3 | the Forever HUD dead-slot filter dropped | `tests/hunter_state.lua` (2), `tests/hud_state.lua` (4) |
| 4 | the HUD's Steady runtime re-point dropped | `tests/hunter_state.lua` (1: "the client's own Steady rank re-points the HUD slot") |
| 5 | the Forever Steady cast-time fallback restored | `tests/hunter_state.lua` (1) |
| 6 | one rotation row loses its `engine` flag | `tests/hunter_state.lua` (2), `tests/hunter_guide_state.lua` (1) — the hole the old truthiness test hid |
| 7 | the filed row's `needs` emptied | `tests/hunter_state.lua` (3), `tests/hunter_guide_state.lua` (1) |
| 8 | the guide slot's family-aware fallback back to 56641 | `tests/hunter_guide_state.lua` (2) |

## 5. Validation

* `bash tests/run.sh` → **41 steps, 0 failed** (the floor).
* `luacheck .` → **2 warnings / 0 errors in 83 files** (the standing floor; both
  warnings are pre-existing, in `compat.lua` and `main.lua`, files this lane never
  touched).
* Line endings preserved: `classes/hunter.lua` and `hunter_guide.lua` are CRLF
  (0 bare LF); the three test files are LF, as they were.
* No git commands were run beyond reading the working-tree diff for review.

**Everything above is verified OFFLINE only.** The in-client behaviour is
UNCONFIRMED: the operator's session is the only thing that can confirm it.

## 6. Residuals filed (NOT built here — out of this lane's scope)

1. **The other HUD slots are still family-blind.** Only the Steady slot was
   ordered and corrected. On the Forever client the HUD still ships Raptor Strike
   2973 (the client knows 27014), Kill Command 34026 / Bestial Wrath 19574 /
   Rapid Fire 3045 (TBC-era spells the Forever client does not have) and Aimed
   Shot 19434 (the Era spell). Those slots resolve to no name either, so they
   show no cooldown. The same runtime re-point would fix them the way it fixed
   Steady — the hunter's own rank tables already carry the right ranks
   (`raptor_strike_ids` has 27014 and 14266). **Filed, not built:** the brief
   scoped the HUD work to the Steady slot, and the other slots need their own
   family decisions (which of them are dead on which family).
2. **The Era client's Steady Shot existence is UNCONFIRMED.** The shipped tree
   drops the Steady slot on Era ("Steady Shot does not exist on Era") while the
   gather's range probe reads 56641 there — the two statements contradict each
   other. `bench/rogue_hunter_eratbc_2026-10-19.md` §5 (H-HUD-1) asserts "56641
   has no Era existence", but that is a bench claim, not a client read, and
   vanilla 1.15 carried a Steady Shot. This lane kept the Era behaviour exactly
   as it was (the probe still reads 56641; the slot is still absent). The
   observation that settles it: `GetSpellInfo(56641)` on the 1.15.9 client. If the
   Era client HAS it, the Era guide would prompt a "steady" action with no slot to
   show it (the engine's rule 6c is not family-gated).
3. **The TBC Arcane Shot row is a dormant arm.** Its own `source` says the engine
   never prompts it (`TBC_ARCANE_ENABLED = false`), yet the row declares
   `engine = true` (the arm exists, rule 5c) and the TBC practice panel therefore
   shows an Arcane Shot button the engine never asks for. Making it
   `engine = false` would remove a button from the practice panel — a
   default-visible change in a surface this lane must not touch — so the shipped
   behaviour was kept and the flag was declared honestly (arm present, plug off).
   **The operator may rule on it.**
4. The `CHANGELOG.md` / `TESTING.md` release notes were **not** touched (docs are
   out of this lane's scope). The changelog already states the corpus correction
   (TBC 34120; the Forever client has no Steady Shot) — this lane makes the tree
   and the suite agree with it.

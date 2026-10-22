# The truth pass's P9–P12 merged into the live script (2026-10-20)

**Desk:** a subagent lane under the orchestrator · **Source of the probes:**
`bench/perclient_truth_final_2026-10-20.md` §6 (the operator handover; the rows themselves
are **reconstructed** there from `bench/final_gate_audit_2026-10-20.md` §6's C3–C6).
**Deliverable:** `bench/live_test_script_2026-10-19.md` — the only file changed. **No `.lua`,
no test, no other bench file, no `desks/`, no `hands-up.md`, no git write.**
**Validation owner: orchestrator.**

---

## 1. What was merged, and where

| probe | where it landed in `bench/live_test_script_2026-10-19.md` | shape |
|---|---|---|
| **P9** — the Consecration **icon** press | **§1 step 10** (paladin; new step, appended) | Where / How / Expect / A defect is / Report / status |
| **P10** — the Cata/Mists **Seal of the Crusader** button | **§1 step 11** (paladin; new step, appended) | same |
| **P11** — the Cata/Mists **shaman common abilities** | **§3 step 8** (shaman; new step, appended) | same |
| **P12-a…d** — the arity probe, the name probe, the Healthstone id, the **HUD slot ownership** | **§9's new "P12 row" subsection** (after the P10-rows table) | a 5-column table: What to confirm / Exact expected outcome / What counts as a defect / Status going in |

Plus:

* **§4 (hunter) setup line** — one pointer sentence to §9's P12-d row (the hunter's HUD slot
  set is read there). No step renumbered.
* **§10 (report-back format)** — a closing paragraph that names the four answers and the
  step each lives in, and states that **N/A with the client name** is a valid answer.
* **The header** — a fifth "Extended …" block recording what this pass added, and one line
  stating that nothing added here claims in-client proof.

**No existing section or step was renumbered.** The new material is appended inside the
existing structure, so the operator's earlier references (§1.9, §5.6, §7.11, the P8/P9/P10
rows) still line up.

## 2. The label collision (why every new row carries a source tag)

§9 already owns tables called **"P9 rows"** (the APL utility layer) and **"P10 rows"** (the
audit-fix wave). The truth pass uses **P9–P12** for its four in-client probes. The merge
therefore keeps the truth pass's ids (the operator must recognise them) **and** disambiguates
them three ways: the §9 subsection header says which list is which, the §9 subsection states
where the other three live (§1.10, §1.11, §3.8), and every new row carries its source tag
(`… §6 **P9**` / **P10** / **P11** / the truth pass's §6). The header's fifth extension block
repeats the collision note for the operator.

## 3. One correction the merge had to make (worth the orchestrator's attention)

The truth pass's **P12-d** row says: *"**Cata/Mists:** the hunter HUD has **no `raptor`
slot**"*. The **tree** drops that cell on **Mists only**:

* `classes/hunter.lua:3082-3086` — `HUD_DEAD_SLOTS = { ERA = { steady, kill_command },
  FOREVER = { steady, kill_command }, MISTS = { raptor } }`. **CATA is not in the table.**
* `classes/hunter.lua:149-153` — the Cata client's own Raptor Strike rank is **2973**, and
  the cell therefore **ships** on Cata.
* `classes/hunter.lua:2967-2973` — the guide's slot set: `MISTS` gets the raptor-less
  `guide_slots_mists`; **CATA falls through to `guide_slots_base`, which carries the raptor
  slot**.
* `bench/hunter_sod_build_2026-10-20.md` §8 — the lane's own operator checklist says the
  same: **Cata = nine slots** with the Raptor Strike icon at the 2973 texture; **Mists =
  eight slots**, no Raptor Strike cell; **Forever = seven slots**.

Writing "Cata/Mists: no raptor slot" into the script would have sent the operator looking
for a **defect that is not a defect**. The merged **P12-d** row therefore states the tree's
per-family expectation (**Forever seven / Mists eight / Cata nine**, with the Cata raptor
cell expected at the 2973 icon) and carries an explicit NOTE that the audit's C6 wording is
coarser than the tree. The truth pass's file was **not** edited (out of scope) — the
correction is recorded here and in the script.

## 4. The probes as merged (the operator's short list)

| # | the operator runs | the answer that closes it |
|---|---|---|
| P9 | paladin rotation scenario, wait for `next: cons`, press the **icon** button | the panel reads **CORRECT** (`correct: cons`). The defect string is `out of order: wanted cons, cast consecration` — that exact line means HIGH-1's fix did not reach the client |
| P10 | on Cata/Mists: open the paladin practice panel, list every button | **no "Seal of the Crusader" button** (the CATA/MISTS buckets carry no `sotc`; the other ten keys stay). A NEUTRAL on a seal press is the defect — it is a mis-pick (F) there |
| P11 | on Cata/Mists: open the shaman practice panel, list every button | the **five** common abilities are offered — Healing Wave, Chain Heal, Water Shield ("Mana Shield" on SoD), Healing Potion, Food. Any one missing is the defect |
| P12-a | every client: `/run local n,r,i,ct,mn,mx,sid=GetSpellInfo(<ID>); print("SPELLINFO",n,r,i,ct,mn,mx,sid)` (a spell the client **has**) | seven values, `ct`/`mn`/`mx` numbers, `sid` = the id passed → the 7-value shape holds there. `sid` empty → the shape is shorter; record the client and the values |
| P12-b | every client: the `SPELLNAME` ("Fireball") and `SOTC` ("Seal of the Crusader") lines | a name → the global takes names there; `nil` → it does not |
| P12-c | Cata/Mists: the `HS` line (5720 / 6262 / "Healthstone") | which id answers, and whether the **name** answers and to which id (the tree's Cata/Mists claim is 6262 and is **UNPROVEN**) |
| P12-d | every client: the hunter's HUD slot list, all slot toggles at their default | Forever seven (no Steady Shot), Mists eight (no Raptor Strike), Cata nine (the Raptor Strike cell ships at the 2973 icon) |

## 5. Discipline

* **Nothing claims in-client proof.** Every new row is marked **verified offline /
  UNCONFIRMED in-client**, with the source of the offline verification named
  (`bench/grader_seam_2026-10-20.md`, `bench/final_gate_fixes_2026-10-20.md`,
  `bench/perclient_truth_final_2026-10-20.md`).
* **Line endings preserved** — the script stays **LF** (0 CR bytes, checked after the edit);
  no trailing whitespace on any line.
* **No existing line was reworded** — every edit is an append or a one-sentence pointer; the
  touched lines keep their original whitespace.
* **No desk file was written.** The dispatch lists `desks/` as out of scope, so the trail
  lives here and in the central journal (the orchestrator owns the desk ledger).

## 6. Open for the orchestrator

1. **The P12-d wording** (§3 above) — the script states the tree's per-family expectation and
   flags the audit row's coarser wording. If the orchestrator prefers the audit's wording
   verbatim, this row is the one to change; the tree citation stands either way.
2. **The label collision** (§2) — the operator will read "P9"/"P10" in two senses. The merge
   disambiguates in three places; a rename of the truth pass's ids (e.g. **T1–T4**) would
   remove the ambiguity entirely, but that would break the operator's link back to
   `bench/perclient_truth_final_2026-10-20.md` §6.
3. **The central journal** — this lane did not add a lane row (the orchestrator owns
   `desks/journal.md`).

# Rogue Hemorrhage — Journal

## 2026-10-19 — Desk opened
- **Purpose:** build spec **BS-6** of `bench/filed_closure_sweep_2026-10-19.md` §7 — the rogue
  **Hemorrhage** builder (the "Hemo" builder that was excluded as an uncertain name).
- **Scope:** `classes/rogue.lua`, `rogue_guide.lua`, `tests/rogue_state.lua`,
  `tests/rogue_guide_state.lua`. Nothing else. No git, no lint-config change, no TOCs.
- **Key fact (the corpus correction, from the bench + the orchestrator's brief):** the bench
  corpus had the TBC ids **swapped** — `26862` is **Sinister Strike**, `26864` is **Hemorrhage**
  (wowhead's own redirect slugs/pages). The spell is **"Hemorrhage"** (not "Hemo-Ghostly").
  TBC id `26864`; Era/Forever id `16511` — both web-confirmed.
- **Build shape:** the builder candidate chain becomes
  `{ "Saber Slash", "Mutilate", "Hemorrhage" }` + the existing dagger-mainhand `Backstab` + the
  `GUIDE_SPELL_NAMES.builder` (Sinister Strike) fallback, with a **family gate**: Hemorrhage is a
  TBC/Forever/Era builder, never a SoD one — it sits after the rune candidates and before the
  generic Sinister Strike fallback, never ahead of a rune the sim prefers.
- **Rules:** TBC-name / Era-id both pinned; nil-safe; unknown-hides (an unknown name resolves to
  nil and the chain falls through — never a wrong builder); the family gate pinned (SoD never
  picks Hemorrhage over a rune); line endings preserved (the two addon files are CRLF, the two
  test files are LF); touched-lines whitespace only; mutation proofs on `/tmp/opencode` copies.
- **Next step:** implement the gate + the chain, update the two suites, run the harness, prove
  the mutations.

## 2026-10-19 — BS-6 built (Hemorrhage builder + family gate)
- **Worked on:** the builder chain in `classes/rogue.lua` and the pure family gate in
  `rogue_guide.lua`, plus the two rogue suites.
- **What landed:**
  - `classes/rogue.lua:264` — the chain is now literally
    `{ "Saber Slash", "Mutilate", "Hemorrhage" }`; the dagger-mainhand `Backstab` and the
    `GUIDE_SPELL_NAMES.builder` (Sinister Strike) fallback stay behind it.
  - `rogue_guide.lua:508-544` — the new pure gate: `BUILDER_GATED_FAMILIES`
    (`Hemorrhage = { ERA, TBC, FOREVER }`) + `builder_candidate_allowed(name, family,
    sod_envenom)`. An ungated candidate is always allowed; a gated one needs its family row
    and is vetoed on the SoD client (the `"SOD"` token, or the ERA token behind the
    `sod_envenom` latch). An unknown family answers false.
  - `classes/rogue.lua` — `builder_candidate_allowed(name)` asks the engine; the loop skips a
    gated candidate. The engine missing ⇒ the candidate is allowed (the gate is an extra
    safety, never the only one; `rogue_guide.lua` ships in all 7 TOCs anyway).
  - `classes/rogue.lua:1677-1687` — the **SoD latch now runs BEFORE `apply_spell_ids`**: the
    builder's gate reads the latch, and the latch must exist before the ids resolve.
    Behaviour-neutral otherwise (the latch reads only `st.family` + `api.is_spell_known`).
  - The "Hemo-Ghostly is deliberately excluded (uncertain which rank the TBC sim gates)"
    comment is **gone** (both places: the module header and the chain comment). The new
    standing cites the name ("Hemorrhage" — certain) and the ids (TBC 26864, Era/Forever
    16511, web-confirmed; the corpus had them swapped — 26862 is Sinister Strike). The ids
    are **cited, never used**: the class resolves the NAME through the client's own spell
    data, so a wrong id cannot produce a wrong builder.
  - `classes/rogue.lua:2267-2268` — the practice rotation row's `note`/`source` carried the
    **swapped** ids ("Sinister Strike 26864"); it now reads
    "Hemorrhage 26864 / Backstab 26863 / Mutilate 34413 / Sinister Strike 26862" with the
    correction noted. (In-scope file; the bench corpus itself is the orchestrator's.)
- **Pins:** `tests/rogue_state.lua` (796 checks) — the chain row by row (Saber → Mutilate →
  Hemorrhage → dagger Backstab → Sinister Strike), the unknown-hides direction (a Hemorrhage
  the client does not know falls through), the **TBC-name** pin (the slot stores
  `"Hemorrhage"`), the **Era-id** pin (the slot stores the numeric id), the SoD gate (the
  rune still leads; the gate keeps Hemorrhage off SoD), the Wrath gate, the label-follows-the
  -winner pin, and source pins (the chain literal, the two cited ids, "Hemo-Ghostly" gone).
  `tests/rogue_guide_state.lua` (776 checks) — the pure gate: the table shape, the per-family
  verdicts, the SoD veto, the unknown-family false, the ungated-candidate true.
- **Validation:** harness **41 steps, 0 failed**; luacheck **2 warnings / 0 errors** (the
  floor, unchanged). Mutations **7/7 killed** on `/tmp/opencode` copies
  (`/tmp/opencode/bs6_mutations.sh`): chain-without-Hemorrhage, Hemorrhage-first,
  gate-call-removed, gate-keeps-SoD, gate-any-family, latch-after-ids, gate-table-drops-ERA.
- **Current state:** the build is complete and green; the orchestrator owns validation.
- **Two things the operator should know (not blockers, both already in the corpus):**
  1. **The TBC APL's known-spell (talent) branch is still unmodelled.** The class resolves
     "Hemorrhage" by NAME from the client's spell table, so a TBC client that ships the spell
     can answer it even for a character without the Hemorrhage talent. Closing it needs an
     id-based known-spell probe, which the TBC name-vs-id rule discourages. This is the
     already-filed APL-gating row (`bench/class_features_drills_2026-10-19.md:609` R-03) —
     it is not new, and it was out of BS-6's scope.
  2. **The chain order is the spec-literal reading**: Hemorrhage sits *before* the
     dagger-mainhand Backstab ("the candidate chain becomes { Saber Slash, Mutilate,
     Hemorrhage } plus the existing Backstab and the fallback"). The corrected TBC APL
     branch order agrees (Hemorrhage 26864 → Backstab 26863 → Mutilate 34413 → Sinister
     Strike 26862 — the audit's "Hemo-Ghostly fallback (26862)" was Sinister Strike).
- **Deviation from the bench's pin-to-file map:** the bench put "the guide's builder slot id
  follows the winner" in `tests/rogue_guide_state.lua`, but the guide's builder slot is
  class-side (`ST.ROGUE.guide.slots` in `classes/rogue.lua`). That pin therefore lives in
  `tests/rogue_state.lua` (where the slot is) and `tests/rogue_guide_state.lua` carries the
  engine's pure half of the gate.
- **Next step:** the orchestrator validates in-tree (the operator's in-client session is
  still the only truth for the TBC Hemorrhage row).


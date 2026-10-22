# perclient-truth-final — Journal

## 2026-10-20 — Desk opened
- **Purpose:** Run the per-client truth checks the final audits deferred (they had no shell
  access): the classic global `GetSpellInfo` name-vs-id + return arity on all five reference
  branches, the "is the Mists folder's `Blizzard_TalentUI` live on the Era client" question,
  and the Seal of the Crusader / Healthstone spell ids against the operator's own client
  export. Deliverable: ONE new bench file
  `bench/perclient_truth_final_2026-10-20.md` with a row per check (question → evidence →
  quoted text → PROVEN / UNPROVEN / OPERATOR-ONLY), the verdict on the tree's
  `compat.lua:157-176` arity assumption, and the operator's in-client list.
- **Scope:** READ ONLY except the one new bench file. No `.lua` edit, no git write, no
  checkout of `/home/sam/wow-ui-source` (read-only `git show` / `git grep` only). The
  reference repo's checked-out branch (`classic_era`) was never touched.
- **Next step:** execute P1–P8 offline, record the answers with `branch:file:line`, then
  hand P9–P12 to the operator in the live script's step format.

## 2026-10-20 — P1–P8 executed; the arity assumption is neither confirmed nor refuted
- **Worked on:** all five branches read via `git show <branch>:<path>` and
  `git grep <branch>` (`classic_era`, `classic_anniversary`, `classic_titan`,
  `origin/forever`, `live`), plus the operator's own client export at `/home/sam/wow.export`
  (1.15.9 SoD). Wrote `bench/perclient_truth_final_2026-10-20.md`.
- **Findings that changed the picture:**
  - **P2 — the Mists folder is DEAD CODE on the Era client.** The name-form call
    `GetSpellInfo(talentName)` lives at
    `classic_era:Interface/AddOns/Blizzard_TalentUI/Mists/Blizzard_TalentUI.lua:671`,
    and the Era client loads `Blizzard_TalentUI_Vanilla.toc` →
    `Classic\Blizzard_TalentUI.lua`, which has **zero** `GetSpellInfo` calls. The same
    Mists file IS live on **Retail** (`live` ships only `Blizzard_TalentUI_Mists.toc`).
  - **The name question is therefore PROVEN on Retail and UNPROVEN from the tree for
    Era/TBC/Wrath** (no name-form call site in any file those clients load).
  - **The arity is UNPROVEN on every branch**: no call site anywhere unpacks 4+ values from
    the global (checked on all five branches), the global has no Lua definition and no
    documentation entry. Positions 1–3 (name / subname-rank / icon) are proven by call
    sites; 4–7 are an engine-side (C++) fact the tree cannot settle offline.
  - **P7/P8 — the client's own export settles two tree claims and two remain open.** The
    1.15.9 SoD data proves the seal ladder (21082 r1 … 20308 r6, Retribution, named "Seal of
    the Crusader" by the client's own 20335/28852 descriptions) and proves **5720 = the
    Healthstone** and **6262 = the Minor Healthstone** (via 5699/6201's `$5720`/`$6262`
    description tokens) — i.e. the tree's `classes/druid.lua:4231-4233` claim is CONFIRMED.
    Nothing in the export speaks about Cata/Mists.
- **Current state:** the deliverable is on the bench; the tree's `compat.lua:157-176`
  assumption is **not refuted and not confirmed** — recorded with the exact scope of what is
  proven and what stays an operator probe.
- **Next step:** the operator runs the P9–P12 rows (§6 of the bench file) in-client; the
  orchestrator owns the ruling on the arity once the operator's probe is pasted back.

## 2026-10-20 — [signal:done] the final per-client truth pass landed
- `desks/perclient-truth-final/.signals/2026-10-20T23-40-00Z-done.json` — P1–P8 answered
  offline with `branch:file:line` + quoted text on all five branches and against the
  operator's 1.15.9 SoD export; P9–P12 handed over as an executable operator list.
  Deliverable: `bench/perclient_truth_final_2026-10-20.md` (the ONLY bench file written;
  no `.lua`, no test, no other bench file, no git write).
- **Headline answers:** the classic global's **name**-acceptance is **PROVEN on Retail**
  (`live:…/Blizzard_TalentUI/Mists/Blizzard_TalentUI.lua:671` — and that is the *only* live
  global call site on Retail); the Mists folder's TalentUI is **vendored dead code on the
  Era client** (P2); the **arity is UNPROVEN on every branch** (no call site unpacks 4+;
  slots 1–3 are proven, 4–7 are C++-side) → the tree's `compat.lua:157-176` is **neither
  refuted nor confirmed**, and its failure mode is a **silent nil**, so the operator probe
  (P12-a) matters on every client, not only the classic line.
- **Two tree claims upgraded to client-proven:** 5720 = the Healthstone and **6262 = the
  Minor Healthstone** (`Spell.csv` rows 5699 / 6201 carry the `$5720` / `$6262` tokens) —
  the "6262 is a DIFFERENT spell on the classic clients" half of
  `classes/druid.lua:4231-4233` (and its five sibling copies) is now the client's own
  testimony, not a web page; and the seal ladder 21082·20162·20305-20308 is a 6-rank
  **Retribution** family the client itself calls "Seal of the Crusader" (20335 / 28852).
- **Not closed, by construction:** everything about Cata/Mists (the operator's export is
  Era/SoD data) and the engine-side arity → the operator's rows.

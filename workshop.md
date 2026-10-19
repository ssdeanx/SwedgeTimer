# workshop

SwedgeTimer's workshop — the place where the desks work. The philosophy
is in `CAIRN.md`; the operating mechanics are in `AGENTS.md`; this file
is the map.

## the rooms

| room | what it is |
|------|------------|
| `desks/` | where desks work — one directory per desk: `desks/<name>/journal.md` (the desk's memory, opened per `desk-open`) and `desks/<name>/.signals/` (structured JSON signals per `signal-write`). `desks/journal.md` is the orchestrator's central lane ledger |
| `bench/` | the shared results workspace. PRIMARY location for cross-desk artifacts: findings, verdicts, drafts, reports land here as dated, named files; supersede loudly, never overwrite. `bench/briefs/` holds dispatch briefs, `bench/lessons.md` holds earned lessons. Desk-local dirs are secondary |
| `CAIRN.md` | the operating disposition — how a desk stands, the ledger rules, the two-proofs rule |
| `hands-up.md` | the escalation ledger — open disagreements become rows here; the operator rules |
| `AGENTS.md` | operational mechanics: conventions, gotchas, cross-engine rules, research tooling |

## how work flows

1. the brief is written to `bench/briefs/` — verified paths and ids
   only (CAIRN: verify before you reference).
2. the desk is dispatched; its row goes into `desks/journal.md` with the
   session id exactly as returned by the dispatch.
3. the desk reads its own journal (`desks/<name>/journal.md`) to load
   priors, works at its desk, holds scope, leaves findings on the bench,
   and emits signals (`signal-write`: hands-up / blocked / done /
   checkpoint) into its `.signals/` directory as it goes.
4. disagreements that can't be settled against external facts become rows
   in `hands-up.md` (and an `escalation/hands-up` signal).
5. the desk ends by journaling (per `desk-journal`): what was done,
   current state, next step — written for someone starting from zero.
6. the operator reconciles, updates the journal, and decides what
   becomes memory.

## current desks

one directory per desk under `desks/` (kebab-case lane names):
`bars-design`, `compat-bl`, `diag`, `hunter`, `warrior`, `paladin`,
`shaman`, `druid`, `practice`, `enemy-swing`. The central lane table
(state + session ids) lives in `desks/journal.md` — the orchestrator's
ledger and the only authoritative lane table.

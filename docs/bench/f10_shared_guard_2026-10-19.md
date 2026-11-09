# F10 — ONE shared error-isolation contract (2026-10-19)

Desk `f10-shared-guard`. Closes deep-audit finding **F10**
(`bench/deep_audit_2026-10-19.md:28`) and, on the way, the **undefined
`SCENARIO_RESOURCE_KEYS`** crash the orchestrator raised while this lane owned
`practice_ui.lua`.

Verdict: **F10 CLOSED** (one implementation, six call sites migrated, every
isolation pin unchanged and green) **+ the scenario-ctx crash CLOSED**.

---

## 1. What the finding said

> F10 | LOW | `bars.lua:517-541`, `hud.lua:210-260`, `nextaction_ui.lua:728-775`,
> `practice_ui.lua:572-592` **and** `:3966-3998`, `rotationtext.lua:243-283` |
> The `run_guarded` isolation contract is implemented **six times** with six
> quarantine constants — and already diverged (`note_start_block` prints on every
> refusal, the other five print once). | One shared
> `st.guard.run(owner, site, fn, ...)` helper (new root module, all 7 TOCs) with
> per-site message text as a parameter.

The line numbers in the finding were the audit-time ones; the tree has moved since
(the copies now live at `bars.lua:508-524`, `hud.lua:208-215`,
`nextaction_ui.lua:725-736`, `practice_ui.lua:856-867` + `:5564-5586`,
`rotationtext.lua:241-251`). The six copies themselves were verified as described
before anything was changed:

| # | Copy (pre-migration) | Threshold const | Counter bookkeeping | Print policy |
|---|---|---|---|---|
| 1 | `bars.lua` `run_guarded` | `BARS_HOOK_QUARANTINE_THROWS = 25` | own table | first failure once |
| 2 | `hud.lua` `note_hud_error` + `hud_quarantined` | `HUD_QUARANTINE_THROWS = 25` | own table | first failure once |
| 3 | `nextaction_ui.lua` `note_nextaction_error` + `nextaction_quarantined` | `NEXTACTION_QUARANTINE_THROWS = 25` | own table | first failure once |
| 4 | `practice_ui.lua` `note_practice_error` + `practice_quarantined` | `PRACTICE_QUARANTINE_THROWS = 25` | own table | first failure once |
| 5 | `practice_ui.lua` `note_start_block` | (none) | own table | **every refusal** |
| 6 | `rotationtext.lua` `note_rotation_error` + `rotation_quarantined` | `ROTATION_QUARANTINE_THROWS = 25` | own table | first failure once |

Every copy rebuilt the same table shape `{ count, by_site, quarantined,
first_reported }` under the same name (`owner.bar_hook_errors`) and the same
threshold (25). The counters, the site keys and the message texts are the
`/st diag` reader's contract (`main.lua`, `diag.lua` — untouched here).

## 2. The shared implementation — `guard.lua` (NEW root module)

`guard.lua` owns the contract ONCE. What stays at the call site is the site key,
the wording and the degraded result.

| Entry point | Contract |
|---|---|
| `st.guard.run(owner, site, fn, ...)` | pcall + count + report once + quarantine. Results mirror `pcall`'s shape: `(true, ...)` on success, `(false, err)` on a throw, `(false)` for a quarantined site (the call is skipped, nothing is counted). |
| `st.guard.note(owner, site, err)` | records a failure the call site already caught (the practice drill paths keep their own pcall): same counting, same once-only report, same quarantine. |
| `st.guard.refusal(owner, site, msg)` | the refusal flavour (the user-invoked practice start gate): counts + prints **every** time. The divergence the finding named is now an explicit, documented mode of the one implementation instead of a sixth copy. |
| `st.guard.quarantined(owner, site)` | is the site quarantined for this session? |
| `st.guard.label(segment, label)` | the per-call-site wording. The segment is the first part of the site key (`"hud:cs"` → `"hud"`), so a consumer registers its label once. The shared module never hard-codes a module's wording. |
| `st.guard.QUARANTINE_THROWS` | the one threshold (25 — the value every copy had). |

Unchanged on purpose: the counter name (`owner.bar_hook_errors`), the table shape
(`count`, `by_site`, `quarantined`, `first_reported`), every site key
(`zone:<id>`, `class:<CLASS>:on_bar_update`, `ldb:update`, `hud:<slot>`,
`nextaction:gather`, `nextaction:evaluate`, `practice:tick`, `practice:start`,
`rotationtext:get_rotation_key`), every message text, the chat path (the owner's own
`Print` — AceConsole, `DEFAULT_CHAT_FRAME:AddMessage`; never the client's raw global
`print`), and the degraded results (hide / unknown / freeze).

### Migrated call sites

| Module | Before | After |
|---|---|---|
| `bars.lua` | `run_guarded(self, site, fn, ...)` (own pcall + own table) | `st.guard.run(self, site, fn, ...)` ×3 (zone, class hook, ldb feed) |
| `hud.lua` | `pcall(call_hud_provider, …)` + `note_hud_error` + `hud_quarantined` | `st.guard.run(self, site, call_hud_provider, …)`; degrade = `HUD_HIDDEN_STATE` (hide) |
| `nextaction_ui.lua` | `pcall(provider.gather/evaluate, …)` + `note_nextaction_error` + `nextaction_quarantined` | `st.guard.run(self, "nextaction:gather"/"nextaction:evaluate", …)`; degrade = `inputs_unknown` |
| `practice_ui.lua` | `note_practice_error` + `practice_quarantined` + `note_start_block` (two copies of the bookkeeping) | `st.guard.note` / `st.guard.quarantined` / `st.guard.refusal` — the two near-identical copies collapsed into the one helper |
| `rotationtext.lua` | `pcall(RT.decide_update, …)` + `note_rotation_error` + `rotation_quarantined` | `st.guard.run(self, ROTATION_ERROR_SITE, RT.decide_update, …)`; degrade = hide |

`practice_ui.lua`'s drill paths keep their own `pcall` on purpose: each grades
through its own shell and reads its own result, and the source-text pins in
`tests/rogue_state.lua` (an out-of-scope suite) name that exact call shape. The
**accounting** still happens in exactly one place (`st.guard.note`).

## 3. The TOCs

`guard.lua` is listed in **all 7** TOCs, directly after `utils.lua` and before
every consumer (`bars.lua`, `nextaction_ui.lua`, `practice_ui.lua`, `hud.lua`,
`rotationtext.lua`). `tests/toc_check.lua` pins the order (new checks, 865 checks /
0 failures) and the existing "every root module on disk is listed" check covers the
line itself.

## 4. The `SCENARIO_RESOURCE_KEYS` crash (orchestrator's finding, same lane)

`practice_ui.lua:4316` read `SCENARIO_RESOURCE_KEYS` — **defined nowhere in the
tree**. The default scenario ctx builder therefore raised
("attempt to get length of global 'SCENARIO_RESOURCE_KEYS' (a nil value)") on the
first scenario step for every class that does **not** publish its own
`practice_context` — druid, warrior, shaman (only hunter, rogue and paladin publish
one). The raise escaped `scenario_open_step` → `scenario_start_session` → `ui.start`,
so the session never opened.

**The fix** (`practice_ui.lua`):

1. The list is now a **local** definition next to its use, and it is the **verified
   union of the pool readings the six classes' `gather_guide_inputs` actually
   produce** — each class names its own pool, there is no shared name:
   `mana` (hunter), `mana_pct` (paladin), `mana_fraction` (shaman),
   `rage` (druid bear + warrior), `energy` (druid cat), `energy_now` / `max_energy` /
   `cp` (rogue), `combo_points` (druid cat).
   **"focus" is deliberately absent**: no gather produces it (the focus pool lives
   in the engine's own sim state, `practice.lua`'s `new_focus_state`) — verified,
   not guessed.
2. The path can no longer crash: the list is a local (an undefined **global** read
   is impossible again), every lookup is type-guarded, and the lift also copies the
   class's own state beside the pool (numbers, flags and tokens — the same rule the
   rogue's own `practice_context` uses), so a field nobody listed still reaches the
   class's grader. No class degrades to "unknown" over a missing entry.

## 5. Validation

* `bash tests/run.sh` (in-tree, final tree): **41 steps, 0 failed** (twice in a row).
  During the lane the same tree read **41 steps, 2 failed** — both failures were the
  shaman lane's in-flight work (§6); they cleared the moment that lane landed its
  own pin update, with no change from this lane.
* `luacheck .`: **2 warnings / 0 errors in 83 files** — the floor, held (the new
  module follows the shipped `local _, st = ...` shape of `twist.lua`/`weave.lua`,
  so it adds no warning).
* Line endings verified per file before editing: `guard.lua` CRLF (like `utils.lua`,
  its TOC neighbour), `bars.lua` LF, `hud.lua` / `nextaction_ui.lua` /
  `practice_ui.lua` / `rotationtext.lua` CRLF, the 7 TOCs CRLF, the test suites LF.
  No line-ending was changed.
* **Mutation proofs** on `/tmp/opencode` copies (base
  `/tmp/opencode/mut_f10_base`, runner `/tmp/opencode/mut_f10.py`): **9/9 killed**.
  Reproduce from the repo root:
  `rm -rf /tmp/opencode/mut_f10_base && mkdir -p /tmp/opencode/mut_f10_base && tar -cf - --exclude=.git . | (cd /tmp/opencode/mut_f10_base && tar -xf -) && python3 /tmp/opencode/mut_f10.py`
  * M1 the shared guard stops counting → killed by 4 suites (the count pins).
  * M2 the shared guard prints every failure → killed by 4 suites (the once-only pins).
  * M3 the shared guard never quarantines → killed by 4 suites (the quarantine pins).
  * M4 the shared guard stops isolating (no pcall) → killed by 3 suites.
  * M5 the refusal stops printing its reason → killed by `practice_ui_state`.
  * M6 the resource-field list is removed → killed by `practice_ui_state` (the module
    fails to LOAD — a failed check, never a throw).
  * M7 the default ctx lifts nothing → killed by `practice_ui_state` (the new ctx pin).
  * M8 a consumer grows its own threshold again → killed by `bars_state` (the
    "no second quarantine threshold" pin).
  * M9 the TOC drops the guard line → killed by `toc_check` (the new order pin).

## 6. The two red suites (mid-lane) — crossfire, not this lane

For part of the lane `tests/shaman_state.lua` and `tests/shaman_guide_state.lua`
failed while the shaman lane edited `classes/shaman.lua` (the file was mid-edit at
22:18 and again at 22:21):

* `shaman_state`: `drill: a tight weave start grades S (got F, want S)` — the
  class's own drill shell (`ST.SHAMAN.practice_cast`, `classes/shaman.lua`). That
  suite loads `compat.lua`, `weave.lua`, `shaman_guide.lua`, `classes/shaman.lua`,
  `practice.lua` — **none of them touched by this lane**.
* `shaman_guide_state`: `the class module is reachable from the addon namespace` —
  the pin still expects the `st.SHAMAN = ST.SHAMAN` mirror that the shaman lane
  deliberately removed (`classes/shaman.lua:4118`: "The namespace mirror this file
  used to carry … is GONE"). Their pin needs updating, not this lane's code.

Both are the sibling lane's own in-flight work; they cleared on their own when that
lane landed its pin update (the final in-tree run is 41/0). The orchestrator
reconciles.

## 7. Files changed (this lane)

* **NEW** `guard.lua`.
* `bars.lua`, `hud.lua`, `nextaction_ui.lua`, `practice_ui.lua`, `rotationtext.lua`
  (the six call sites; `practice_ui.lua` also carries the `SCENARIO_RESOURCE_KEYS`
  fix).
* The 7 flavor TOCs (`guard.lua` after `utils.lua`).
* Suites: `tests/bars_state.lua`, `tests/hud_state.lua`, `tests/practice_ui_state.lua`,
  `tests/rotationtext_state.lua`, `tests/guide_contract.lua` (the suite that owns
  `nextaction_ui.lua`'s pins — `tests/nextaction_state.lua` covers the PURE
  `nextaction.lua` engine, not the UI), `tests/toc_check.lua` (the TOC order pin),
  and the sandbox module lists of every suite that loads a consumer module:
  `tests/designmode_state.lua`, `tests/druid_guide_state.lua`,
  `tests/hunter_guide_state.lua`, `tests/shaman_guide_state.lua`,
  `tests/warrior_guide_state.lua`, `tests/rogue_state.lua`.
* No git, no lint-config change, no version/README/CHANGELOG/docs change, no class
  file touched, no `practice.lua` / `practice_progress*.lua` / `practice_stats.lua` /
  `option_tables.lua` / `config*.lua` / `main.lua` / `diag.lua` / `compat.lua` /
  `tests/run.sh` change.

## 8. New pins (all green)

| Suite | Pin |
|---|---|
| `bars_state` | the shared module owns the threshold / the once-only bookkeeping / the counter table / the `run` entry point; each of the five consumers owns no threshold copy, no counter bookkeeping, and delegates to `st.guard`; the bar wording stays at the call site. |
| `hud_state` | the HUD isolates through the shared guard, keeps no second threshold/bookkeeping, and keeps its wording at the call site. |
| `guide_contract` | the guide (nextaction_ui) isolates through the shared guard, keeps no second threshold/bookkeeping, and keeps its wording at the call site. |
| `rotationtext_state` | the rotation label isolates through the shared guard, keeps no second threshold/bookkeeping, and keeps its wording at the call site. |
| `practice_ui_state` | the practice tick/refusal/quarantine read the shared guard; no second threshold/bookkeeping; **the default ctx path works for a class with NO own `practice_context`** (the warrior fixture: the class is asked, the pool `rage`, the flag `hs_queued` and the state `target_health_pct` reach `ctx.resources`, the remaining cooldown reaches `ctx.cooldowns`); **the undefined-constant crash cannot come back** (the list is a local definition, defined before the code that reads it). |
| `toc_check` | every TOC lists `guard.lua`, loads it after `utils.lua` and before every consumer. |

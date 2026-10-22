# M3 — the spell-knowledge contract in `compat.lua` (2026-10-20)

Desk: `compat-m3` · Scope: `compat.lua`, `tests/secret_guard_state.lua` (the suite that owns
the compat client-profile probes — verified by grep, not assumed) · No git, no class files,
no options/config, no TOCs, no versions, no docs.

## 1. The defect

`compat.lua`'s spell-knowledge comment claimed:

> "the first one that returns a value wins, and a client with none of them reports
> **"unknown"** instead of erroring."  (old `compat.lua:181`)

The code answered **`false`** there (`old compat.lua:208-216`). The behaviour was safe —
every caller treats `false` as fail-closed — but the **contract was wrong**: a caller
could not tell "no probe answered on this client" from "the player does not know the
spell". A future row that must hide when the client cannot answer had no way through the
API.

## 2. The reading I took: **(b) — keep `false`, correct the comment**

The brief offers (a) `nil` for "no probe answered" or (b) `false` + a corrected comment,
and says to prefer (a) only if it is **provably behaviour-neutral across all callers**. It
is not. The full caller census (below) found **two raw consumers** whose behaviour WOULD
change under (a):

| # | call site | consumer | under (a) `nil` |
|---|-----------|----------|-----------------|
| 1 | `classes/rogue.lua:1263` — `inputs.ar_known = api.is_spell_known(ar_query)` (the RAW return) | `rogue_guide.lua:1614` — `if args.ar_known == false then return "gnome_eureka" end` | `nil ~= false` → the "AR is definitely not known" disjunct stops firing → the gnome-Eureka verdict flips on a probe-less client |
| 2 | `diag.lua:506` — `is_known_fn = st.api.is_spell_known` | `diag.lua:482` — `if ok_known and type(known) == "boolean" then known_txt = known and "true" or "false"` | `type(nil) ~= "boolean"` → the readout renders `known=?` instead of `known=false` |

Both consumers are **out of this lane's scope** (class files / `diag.lua` are owned by
sibling lanes), so (a) could not be made behaviour-neutral from inside `compat.lua`.
Therefore **(b)**: the boolean stays binary, and the comment now says what the code does.

### 2.1 The caller census (64 matched lines, comments stripped)

Every line in the shipped tree (root modules + `classes/*.lua`; `docs/` and the archived
`docs/swedge/` addons excluded) that mentions `is_spell_known` with the comments stripped —
**64 lines**: 3 are text inside strings (`classes/druid.lua:3295`,
`classes/rogue.lua:2616`, `classes/warrior.lua:732`), 2 are the wrapper definitions
(`classes/paladin.lua:196`, `classes/warrior.lua:212`), leaving **59 consumer lines**.
Classified by how the result is consumed:

* **Truthiness / `== true` / `~= true` / normalised** (52 of the 59) — `nil` and `false` are
  equivalent to Lua, so (a) would be behaviour-neutral here. Verified in
  `classes/druid.lua:1792,2302,2321`, `classes/hunter.lua:1085,2061,2149`,
  `classes/paladin.lua:197,532,1591,1611,2377,2443,2467,2495,2588,2592,3228,3309,3384,
  3386,3406,3806,3934,4041,4150,5135`, `classes/warrior.lua:213,298,934,947,948,1380,3631,
  3722,3829`, `classes/rogue.lua:410,1042,1100,1889`,
  `classes/shaman.lua:512,527,1612,2383,2812,3093,3110,3278,3478,3511,3536,3538,3886`,
  `weave.lua:96` (`get_mw5_spender`: `if lava_burst_known ~= true then`), and the pure
  engines' arms (`rogue_guide.lua:954,1201,1247,1288,1305`).
* **Raw result handed to a consumer (7 of the 59)** — `classes/rogue.lua:1063,1075,1087,
  1113,1132` (the readiness fields `ar_ready` / `bf_ready` / `shiv_ready` /
  `coldblood_ready` / `tea_ready`) and `diag.lua:506`. Five of these are safe under (a):
  the engine tests them with `~= true` (`rogue_guide.lua:954,1201,1247,1288,1305`), where
  `nil` and `false` are equivalent. **Two are not** — the rows in §2.

## 3. What landed

### 3.1 `compat.lua` — the contract, stated and implemented (`compat.lua:178-252`)

* The comment now states the contract the code implements, in the file's own words:
  **binary, never nil** — `true` = a probe answered "known"; `false` = a probe answered
  "not known" **OR** no probe could answer (no probe on the client, or every probe
  declined). A `false` on a client that cannot answer is the **fail-closed answer, not a
  fact about the player**.
* `api.is_spell_known_state(spell_id)` (`compat.lua:234`) — the tri-state, the same shape
  as the repo's own `api.get_family_spell_id_state` (added by the compat-f4 lane for the
  same "could not answer vs. no" problem): `true, "known"` / `false, "not_known"` /
  `false, "unknown"`.
* `api.is_spell_known(spell_id)` (`compat.lua:249`) — unchanged behaviour, now the answer
  half of the state accessor (one implementation, not two).

**No existing caller was touched.** The state accessor is additive and inert today: it
exists so the distinction is *observable* for the future row the audit was about.

### 3.2 The pins (`tests/secret_guard_state.lua`, §10 "R7" + new §10b)

* R7 extended with the state matrix: an answering probe → `"known"`; an answered "no" →
  `"not_known"`; **no probe / every probe declining → `"unknown"`**; the ignored
  `C_Spell` namespace → `"unknown"`; a **declining** probe (returns `nil`) → the chain
  moves on to the next probe. A new sandbox knob `known_declines` proves the decline path.
* A **type** pin on every profile: `api.is_spell_known` returns a **boolean**, never nil —
  the property the two raw consumers depend on.
* New §10b "M3: the spell-knowledge contract": the comment half of the section is scanned
  (comment lines only, so the code's own string literals cannot satisfy a comment pin) and
  must state the binary contract, name the `not_known` / `unknown` states, and NOT carry
  the stale `reports "unknown"` claim.
* The **consumer shapes** are pinned too, so the justification for the binary contract
  cannot silently rot: `classes/rogue.lua` must feed the RAW return into `inputs.ar_known`
  (the exact line — a normalisation there fails the pin), `rogue_guide.lua` must test
  `args.ar_known == false`, `diag.lua` must keep its `type(known) == "boolean"` check.

## 4. Proof

| Proof | Result |
|---|---|
| `bash tests/run.sh` (whole harness) | **41 steps, 0 failed**; luacheck **2 warnings / 0 errors** in 83 files (the floor, unchanged) |
| `tests/secret_guard_state.lua` | **PASS, 410 checks** (was 373 before this lane) |
| Behavioural equivalence, baseline vs. current `compat.lua` (`/tmp/opencode/m3_equiv.lua`) | **PASS, 150 checks, 0 failed** — 8 client profiles × 4 ids: the boolean answers IDENTICALLY in every profile, is always a boolean, and the state accessor always agrees with it |
| Mutation proofs (`/tmp/opencode/m3_mut_run.sh`, on copies) | **10/10 killed** |

The mutations (each must make `tests/secret_guard_state.lua` fail):

| # | mutation | killed by |
|---|---|---|
| m1 | the stale `reports "unknown"` claim returns to the comment | the stale-claim pin |
| m2 | the contract sentence is deleted from the comment | the binary-contract pin |
| m3 | the `"not_known"` state name is deleted from the comment | the state-name pin |
| m4 | the code folds `unknown` into `not_known` | the three state pins |
| m5 | the boolean folds the third state into `nil` (reading (a)) | the boolean + type pins |
| m6 | the state accessor is deleted | the section pin + the state pins (the wrapper then calls a nil field) |
| m7 | the state accessor lies about a known spell | the four `"known"` state pins |
| m8 | `rogue_guide.lua` changes `ar_known == false` to `~= true` | the consumer-shape pin |
| m9 | `diag.lua` changes the boolean check to a nil check | the consumer-shape pin |
| m10 | `classes/rogue.lua` normalises the raw return (`== true`) | the raw-feed pins |

The equivalence proof loads the **baseline** `compat.lua` (the tree before this lane) and
the **current** one into two sandboxes and compares the answers profile by profile — the
"behaviour must not change for any existing caller" requirement, checked rather than
asserted.

## 5. Client truth (why the no-probe path is defensive-only)

Read from `/home/sam/wow-ui-source` per branch (`git show <branch>:<path>`):

* `C_SpellBook.IsSpellKnown` is documented on **every** targeted family and returns a
  **bool**: `classic_era` (`SpellBookDocumentation.lua:82`),
  `classic_anniversary` (`:82`), `classic_titan` (`:82`), `forever` (`:738`),
  `live` (`:684`) — the namespace is `C_SpellBook` (`SpellBookDocumentation.lua:5` on
  classic_era).
* The classic global `IsSpellKnown` is Blizzard's **deprecated shim** over
  `C_SpellBook.IsSpellInSpellBook` (`Blizzard_DeprecatedSpellBook/Deprecated_SpellBook.lua:16-20`),
  and it exists only while the `loadDeprecationFallbacks` CVar is on (`:4-6`).
* So a **probe-less client does not exist in the shipped matrix**: the modern namespace is
  always there, and even the deprecated global's absence does not empty the chain. The
  no-probe branch is the defensive path — which is why the contract, not the frequency,
  is what this lane fixed.

### 5.1 Correction note (2026-10-20, desk `perclient-api-truth`)

A read-only publish-gate re-audit disputed the two citations above on the strength of an
AST-pattern search over the checked-out `classic_era` tree, and asked for this section to
be re-cut. **Both of its premises are refuted by the reference tree itself**; the claim
above stands unchanged, and the per-branch evidence is now recorded in full in
`bench/perclient_api_truth_2026-10-20.md` (checks 1–7).

* *"on `classic_era` that file carries **no** `IsSpellKnown` entry"* — **false.**
  `Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellBookDocumentation.lua:82` on
  `classic_era` reads `Name = "IsSpellKnown",` (the block `:81-96`, returning
  `{ Name = "isKnown", Type = "bool", Nilable = false }` at `:94`). The working tree
  matches the branch (`git diff classic_era -- <file>` is empty), so the entry is present
  there too. A search for the *call* pattern cannot see it: the doc tree names the
  function in a **string literal inside a table constructor**, not as a call.
* *"the string `loadDeprecationFallbacks` appears nowhere in the tree"* — **false.** It
  occurs in **33 files** on `classic_era` (33 / 33 / 31 on `classic_anniversary` /
  `classic_titan` / `origin/forever`, 40 on `live`), including
  `Blizzard_DeprecatedSpellBook/Deprecated_SpellBook.lua:4` itself and
  `Blizzard_Deprecated/Deprecated_1_15_8.lua:5`. The gate is on **all five** branches,
  not four.

Two facts the re-audit did not reach, added here for the record:

* `C_SpellBook.IsSpellKnownOrInSpellBook` — the sibling probe `compat.lua` uses third —
  **is** present on `classic_era` (`SpellBookDocumentation.lua:98`; also `:98` on
  `classic_anniversary` / `classic_titan`, `:755` on `origin/forever`, `:701` on `live`).
  It is the loosest of the three probes (known **or** in the spellbook, overrides
  included), so the chain order (global → `IsSpellKnown` → `IsSpellKnownOrInSpellBook`)
  only reaches it when the first two are absent or decline.
* The classic global answers `C_SpellBook.IsSpellInSpellBook(..., includeOverrides =
  false)`, not `C_SpellBook.IsSpellKnown` — the shim's own body, `Deprecated_SpellBook.lua:16-20`.
  The two questions differ for temporarily-granted abilities and for override spells.
  Behaviour is unaffected (the first probe that answers wins), but the difference is now
  written down instead of implied.


## 6. Open for the operator

* **The state accessor is inert today.** The brief said "add the tri-state only where a
  caller actually needs it"; no caller needs it *yet* (the future row the audit was about
  does not exist). It was added anyway because (a) the objective asks for the contract to
  be explicit where a future row needs it, (b) the repo already ships this exact pattern
  (`api.get_family_spell_id_state`, compat-f4 lane), and (c) it is the only way to make
  the distinction observable **without touching a single caller**. Raised as a hands-up row
  (HU-15) so the operator can rule: keep the additive accessor, or drop it and leave the
  contract binary-only.
* **Cross-lane pin coupling.** §10b pins three lines in files other lanes own
  (`classes/rogue.lua:1263`, `rogue_guide.lua:1614`, `diag.lua:482`). If a sibling lane
  rewrites one of them, this suite goes red — that is the intended signal (the contract's
  justification changed and must be re-decided), but the owning lane should expect it.
* **The pins are in `tests/secret_guard_state.lua`, not `tests/smoke.lua`.** Verified by
  grep: `smoke.lua` owns family detection / spell-id resolution and has no
  `is_spell_known` pin; the spell-knowledge probes live in `secret_guard_state.lua` §10.

## 7. Files changed by this lane

* `compat.lua` — the spell-knowledge comment (`:178-202`), the state accessor
  (`:229-245`), the boolean wrapper (`:247-252`). LF endings kept (CR count 0), tab
  indentation kept, no trailing whitespace, no other line touched.
* `tests/secret_guard_state.lua` — the sandbox knob `known_declines` (the classic probe
  may decline), the R7 state/type pins, the new §10b contract block. LF endings kept, no
  trailing whitespace, no other line touched.

Nothing else. No git commands were run in this repo.

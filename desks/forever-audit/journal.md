# forever-audit — Journal

## 2026-11-06 — Desk opened (written by the session that worked it)

- **Purpose:** read-only audit of the WoW Forever (Camelot 1.60.1 / Interface 16001)
  display pipeline for three operator symptoms: (A) Auto Shot fires but the ranged
  swing bar sometimes does not show it, (B) the horizontal range indicator
  (`weave_range.lua`) worked then stopped displaying, (C) the power bar never shows.
- **Scope:** audit + ranked report only. No product code, tests, TOCs, bench history
  or git. Desk files: `bench/forever_display_audit_2026-11-06.md` (deliverable),
  this journal, `.signals/`.
- **Priors read:** `desks/journal.md` (2026-11-03 reconcile + 2026-11-06 dispatch and
  operator clarifications), `bench/lessons.md`, `AGENTS.md` (Cross-engine + Gotchas),
  the three Forever desk journals (`forever-guide-ui`, `forever-secrets`,
  `release-217`). No answered question was re-searched.
- **Next step (at open):** trace `swing_source.lua` → `main.lua` START/visibility and
  `weave_range.lua`/`power_bar.lua` gates; verify every Forever API claim against
  `origin/forever`; write the ranked report.

## 2026-11-06 — [signal:done] Forever display audit complete

- **Worked on:** full read-only trace of the three pipelines plus the Forever API
  verification on `git -C /home/sam/wow-ui-source show origin/forever:<path>`
  (`eac30af59 1.60.1 (70790)`). Deliverable:
  `bench/forever_display_audit_2026-11-06.md` (ranked findings, exact file:line,
  minimal fix proposals, UNVERIFIED list, red-zone contract verdict, corrections to a
  parallel draft).
- **Key results:**
  - **C-1 (HIGH):** power bar is blocked structurally, not by a missing API: compat
    nils secret `UnitPower`/`UnitPowerMax` (`compat.lua:599-624`) and `power_bar.lua`
    paints with texture arithmetic (`:89-124`, `:333-374`, `:418-423`). Pass-through
    IS the client-supported path: `StatusBar:SetMinMaxValues`/`SetValue` accept secrets
    from tainted code (`SimpleStatusBarAPIDocumentation.lua:229-232`, `:355-358`) and
    Blizzard's own power bar does exactly that (`Blizzard_UnitFrame/Mainline/UnitFrame.lua:939-975`).
  - **A-1/A-2 (HIGH):** a single `PLAYER_SWING` reject is silent for one shot
    (`swing_source.lua:94-141`, `:206-229`), and the visibility driver can die for the
    session because `set_bar_visibilities`/`handle_oor` run outside the pcall and the
    re-arm is last (`main.lua:2793-2828`).
  - **B-1/B-6 (HIGH):** `weave_range.init` sits in `post_init`'s unguarded tail
    (`main.lua:1044-1051`) and the driver self-quarantines after 25 throws
    (`weave_range.lua:469-497`, removes its own OnUpdate).
  - **A-3 (HIGH/MED):** `has_weapon` is derived from secret-capable stat reads and a
    nil is read as "no weapon"; re-probed only on an equipment change
    (`main.lua:986-1012`, `:3011`; `bars.lua:224-228`).
  - **Contract PASS:** the Auto Shot red zone / hidden window / cast bar are
    display-only and cannot hide the bar (verified, §8 of the report).
- **Current state (verified in-tree at write time):**
  - Report written; no product/tests/TOCs/git touched; only desk files are new.
  - Tree is in flight from parallel lanes: at 19:11Z all seven TOCs line 6 +
    `main.lua:5` read **2.2.0** (uncommitted), while `desks/release-version/journal.md`
    records the operator-approved **2.1.8** and the dispatch baseline says 2.1.7.
    **This desk makes no version claim**; re-check before publishing.
  - The other desk's draft `bench/swedge_addon_audit_forever_display_2026-11-06.md`
    was **not edited** (not this desk's file); its two factual errors are corrected in
    §11 of this report.
- **UNVERIFIED (needs the operator's client):** what the dropped ranged payload looks
  like (V1, `/st diag` payload counters), `C_Spell.IsAutoRepeatSpell("Auto Shot")` vs
  `(75)` (V2), `UNIT_TARGET("player")` coverage (V3), the actual secret predicates at
  the hide moment (V4, `C_Secrets.*`), and whether `UNIT_SPELLCAST_SUCCEEDED(75)`
  fires per shot (V5). Exact `/run` probes are in §10 of the report.
- **Next step:** the fix lanes own disjoint scopes per `desks/journal.md` (display fix:
  `main.lua` + `hunter_ui.lua` + `weave_range.lua` + `classes/hunter.lua` + tests;
  power-bar fix: `power_bar.lua` + `compat.lua` + tests). Two items need an operator
  ruling before code: (1) may `weave_range` render an explicit unknown face instead of
  hiding on `checkedDistance == false` (B-5), and (2) should the Forever engine stop
  clearing cycles on combat exit (A-5). After the fixes, one Forever in-client pass with
  `/st diag` verbose closes V1–V5.

## 2026-11-06 — [signal:done] secret-API matrix (second read-only task)

- **Worked on:** a complete secret-API matrix for WoW Forever on the *settled post-fix
  tree* (the 2026-11-06 fix desks landed `compat.lua`, `power_bar.lua`, `main.lua`,
  `bars.lua`, `hunter_ui.lua`, `weave_range.lua`, `swing_source.lua`,
  `classes/hunter.lua`, `diag.lua`, `utils.lua`). Deliverable:
  `bench/secret_api_matrix_2026-11-06.md` (300 lines):
  - Matrix A (unit state/identity/resources/stats), B (auras/casts/events),
    C (cooldowns/charges/duration objects), D (items/totems/combat log): API |
    `origin/forever` predicate (branch:path:line) | compat today | consumers | loss |
    safe sink | minimal fix | severity.
  - Pass-through sink matrix (every widget annotation, tainted vs untainted): StatusBar
    SetValue/SetMinMaxValues/SetStatusBarColor (YES, implemented), FontString
    SetText/SetTextToFit (YES for secret **strings**), SetFormattedText (**NO for
    `("%d", secret)`** — the Forever signature takes one cstring arg; keep `"?"`),
    SetAlpha/SetAlphaFromBoolean (YES, sanctioned), SetVertexColor/SetColorTexture/
    SetDesaturated/SetTexCoord/SetTexture (YES), SetShown (NO), geometry setters (NO),
    CooldownFrame SetCooldown* (NO — untainted-only + protected), geometry/level/strata
    getters (`SecretWhenAnchoringSecret`/`SecretReturnsForAspect` — safe only for
    addon-owned frames).
  - Direct-call audit (alias-aware): hunter `UnitGUID("target")` ×3 + `UnitIsUnit`
    compound token, druid raw GUID, `forever_guide` raw `UnitCreatureType` = the real
    THROW-RISK sites; main.lua CLEU target GUID + hud CLEU GUID are dead on Forever;
    UnitClass("player")/GetSpellTexture sites are rule-only.
- **Top new findings:** SEC-1 hunter raw target GUID (HIGH), SEC-2 compound UnitIsUnit
  (HIGH), SEC-3 unguarded UnitCreatureType in forever_guide (HIGH), SEC-4 classic
  `UnitAura` branch lacks the C_Secrets precheck/pcall (HIGH latent, shim-dependent),
  SEC-6 26/28 cooldown reads ignore the `restricted` fifth return (MED,
  READY-ON-UNKNOWN), SEC-7 the three hunter_ui aura scans `break` on a restricted row
  (TRUNCATION, MED), SEC-8/9/10 totem/mana-pct/trinket nil-vs-unknown guesses (MED).
- **Current state:** report written; no product/tests/TOCs/git touched; only the report,
  this journal and a done signal are new. Tree still in flux (version fields 2.2.0
  uncommitted vs the release-version desk's approved 2.1.8 — no version claim here).
- **Next step:** the Lead dispatches the secret-consumer fix desk from §11's order
  (SEC-1/5 GUID routing first, then SEC-2/3 guards, SEC-4 pcall, SEC-7 breaks, SEC-6
  shared restricted-aware helper, then the additive flags). The in-client `/st diag`
  secret line (`diag.lua:754-789`) + the `/run` probes in §9 close V1–V8.
- **Note:** `desks/secret-consumers-audit/` exists but was empty at write time — if a
  second desk is auditing the same consumers, reconcile before both file fixes.

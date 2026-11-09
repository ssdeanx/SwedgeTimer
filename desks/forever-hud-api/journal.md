# forever-hud-api — Journal

## 2026-11-08 — Desk opened (task t1, `swedge-forever-hud` team)

- **Purpose:** read-only research lane. Produce the citation-backed Forever-only API
  contract for the HUD's cooldown swipes, countdown text and global cooldown under the
  secret-value regime, plus the cache rules. **No product edits.**
- **Scope:** read `/home/sam/wow-ui-source` (`origin/forever`, read-only git),
  `/home/sam/SwedgeTimer` (read-only), `/home/sam/SuperSwingTimer-WoW` (prior art only).
  Write exactly three things: `bench/forever_hud_api_2026-11-08.md`, this journal, one
  done signal. No web search.
- **Priors read first:** `desks/journal.md` tail (2026-11-06 secret wave + 2026-11-07
  Forever range/power/TOC), `bench/lessons.md`, `bench/secret_api_matrix_2026-11-06.md`
  (whole file), `bench/secret_hud_fix_2026-11-06.md`/`secret_consumers_audit` headers,
  `bench/briefs/brief_forever_hud_api_2026-11-08.md`. No answered question was re-searched;
  two prior conclusions are superseded (below).
- **Client identity verified before any claim:** `git -C /home/sam/wow-ui-source log -1
  origin/forever` → `eac30af597e5aaa43a60f6675ef5fdcea100375f 2026-11-04 1.60.1 (70790)`;
  `version.txt` = `1.60.1.70790`.

## 2026-11-08 — [signal:done] Forever HUD cooldown/GCD/secret API contract delivered

- **Worked on:** the full question set A–D of the brief against the generated API docs and
  Blizzard's own Forever Lua call sites, then the addon-side cache audit in
  `hud.lua` / `LibGlobalCooldown.lua` / `compat.lua` / `diag.lua` / `classes/*`.
  Deliverable: `bench/forever_hud_api_2026-11-08.md` (§1 scope, §2 restriction states,
  §3 cooldown read matrix, §4 duration-object verdict, §5 countdown text verdict,
  §6 GCD verdict + wiring, §7 trinket/item verdict, §8 cache matrix, §9 decision table,
  §10 in-client probes P1–P11, §11 UNCONFIRMED register U1–U12).
- **Key results (all cited `origin/forever:<path>:<line>` in the report):**
  - **The swipe IS achievable while restricted.** `C_Spell.GetSpellCooldownDuration`
    (`:326-343`) carries **no** `SecretWhenCooldownsRestricted` (contrast
    `GetSpellCooldown` `:312`), so its `LuaDurationObject` is a plain handle whose *values*
    may be secret (`HasSecretValues`, `LuaDurationObjectAPIDocumentation.lua:350-364`).
    `CooldownFrame:SetCooldownFromDurationObject` (`FrameAPICooldownDocumentation.lua:307-318`)
    is the only cooldown setter **without** `SecretArgumentsAddAspect` — it never carries a
    secret argument. `SecretArguments = AllowedWhenUntainted` refuses *secret arguments*
    from tainted execution only; Blizzard says so in prose at
    `Blizzard_UnitFrame/Shared/UnitFrameUtil.lua:487`. **This supersedes
    `bench/secret_api_matrix_2026-11-06.md:156` and `bench/secret_hud_fix_2026-11-06.md:17`
    ("the HUD swipe cannot be driven from a restricted read") — corrected with evidence.**
  - **Countdown text has a sanctioned no-Lua path:** `C_DurationUtil.CreateDurationTextBinding`
    (`DurationUtilDocumentation.lua:20-29`) + `SetFontString`/`SetDuration`/`SetFormatter`
    (plain args) + `C_StringUtil.CreateSecondsFormatter` (`StringUtilDocumentation.lua:30-39`),
    and the warn colour via `SetTextColorCurve` + `C_CurveUtil.CreateColorCurve`
    (`DurationTextBindingObjectAPIDocumentation.lua:304-315`). The addon must never format
    a secret number (`SecondsFormatter:Format` is `AllowedWhenUntainted`, `:106-123`) and
    must never read the text back (`GetText` → `SecretReturnsForAspect {Text}`, `:352-365`).
  - **GCD:** detection without a number is documented — `SpellCooldownInfo.isOnGCD` and
    `.isActive` are `NeverSecret` (`SpellSharedDocumentation.lua:26,30`); the swipe comes
    from `GetSpellCooldownDuration(probe, false)` (`ignoreGCD` default false). The concrete
    reason GCD is dark today: `LibGlobalCooldown.poll_gcd` (`:152-171`) reads
    `api.GetSpellCooldown`, which compat answers as `0,0,0,0,true` under restriction
    (`compat.lua:471-473`) → the `== 0` early-out means `gcd_duration` never arms.
  - **Trinkets: no duration object exists** (enumerated every `LuaDurationObject` returner
    in the branch — none is an item cooldown) and no item secrecy predicate exists.
    **Contract bug found:** on this client the 4th return of `GetInventoryItemCooldown` is
    `isOnGCD` (Blizzard's own Forever code, `Blizzard_CooldownViewer/CooldownViewer.lua:1017,1021`),
    but `compat.lua:1565-1584` + `hud.lua:341-350,418-431` read it as `restricted` → the
    trinket slot paints the grey unknown face and drops its swipe for the whole GCD window.
  - **Cache rules:** the operator's worry is documented at
    `Blizzard_AuraContainer/Blizzard_AuraContainerGroups.lua:12-25` (a secret table *key*
    makes every access produce secrets and hard-errors) and
    `Blizzard_CooldownViewer/CooldownViewerSecure.lua:3-36` (the secure `secretunwrap` +
    `settablesecurity` pattern). An addon **cannot** use it: `secretunwrap = nil` in
    `Blizzard_EnvironmentCleanup/Mainline/EnvironmentCleanup.lua:280`. `scrubsecretvalues`
    and `issecretvalue` survive, so the addon rule is prove-plain-or-drop. Every existing
    cache group is mapped with its minimal fix (§8.2–§8.4).
- **Current state:** report written and self-checked against the branch. No product file,
  test, TOC, doc or git state touched. Two prior bench conclusions are superseded with a
  loud pointer (§0).
- **Next step (for the implementer / next lane):** run the P1–P11 probes in one Forever
  session and record the printed lines as the evidence note; then implement the
  object-channel wiring of §6.4 behind Forever + `C_Spell.GetSpellCooldownDuration` probes,
  fix the trinket 4th-return contract, and keep every non-Forever path byte-identical.
  **Do not** start from `SetCooldownFromDurationObject` alone: re-verify U3 (does a tainted
  caller get an error or a swipe) before shipping the restricted face.
- **Open (UNCONFIRMED, client-only):** U1–U12 in the report §11, each with its exact probe.
  Nothing in this lane is blocked on them — they change the *face*, not the design.

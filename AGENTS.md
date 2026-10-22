# SwedgeTimer

WoW addon (Lua) shipping one universal build for the classic-line and Mainline client families (see the Cross-engine section for the target matrix). Vendored Ace3 and other libs. There is no build step; offline checks live in `tests/` (`bash tests/run.sh`), and the real check for API behaviour is loading the addon in a client.

## Layout

- Active addon is the repo root; `SwedgeTimer.toc` (base) plus the flavor variants (`SwedgeTimer_Vanilla/_TBC/_Wrath/_Mainline/_Cata/_Mists.toc`) are the authoritative load orders. The client picks one by flavor dispatch: game-type suffix > family suffix > base.
- `main.lua`: addon object, WoW/lib event wiring, swing-timer/range/GCD orchestration.
- `bars.lua`: frame construction, layout, `OnUpdate`, textures/texts.
- `config_presets.lua`: AceDB defaults (`ST.class_defaults`, `ST.bar_defaults`, per-class `ST.<CLASS>.defaults`).
- `config.lua`: wraps the above into `ST.defaults`.
- `option_tables.lua` + `option_table_presets.lua`: AceConfig settings UI.
- `classes/{druid,hunter,paladin,rogue,shaman,warrior}.lua`: class-specific colors/procs; only these six classes have logic.
- `utils.lua`, `LibLatencyMonitor.lua`, `LibGlobalCooldown.lua`: helpers.
- `twist.lua`: pure paladin seal-twisting logic (twist window, attempt/success detection, impossible-twist heuristic). WoW-free by design; unit-tested by `tests/twist_state.lua`.
- `weave.lua`: pure shaman spell-weaving math (breakpoint marker fraction, clip/safe-window math, haste/Maelstrom cast-time model). WoW-free by design; unit-tested by `tests/weave_state.lua`.
- `nextaction.lua`: pure paladin next-action-guide engine (rotation-pattern tables + the full decision model). WoW-free by design; unit-tested by `tests/nextaction_state.lua`.
- `rogue_guide.lua`: pure rogue next-action-guide engine (pool-vs-spend, Rupture-vs-Eviscerate on TTD, per-client Envenom rules, EA/Shiv/Tea rules). WoW-free by design; unit-tested by `tests/rogue_guide_state.lua`. `classes/rogue.lua` wires it to the guide frame via `ST.ROGUE.guide` + `gather_guide_inputs`.
- `nextaction_ui.lua`: the guide frame (CS/Command/Blood/twist icons, HOLD/RIDE overlay, rotation text, cooldown swipes), initialised and driven from `classes/paladin.lua`.
- `swing_source.lua`: the WoW Forever swing engine (native `PLAYER_SWING`), mirroring the `LibClassicSwingTimerAPI` callback surface so `main.lua` runs unchanged there; inert on every other family.
- `compat.lua`: the single cross-client layer — family detection (`st.family`, `st.is_retail`, `st.is_mainline`), normalized `st.api.*` wrappers, `st.gcd_probe_spell_id`. Never call a cross-client API directly elsewhere; go through `st.api`.
- `tests/`: offline verification — `smoke.lua` (client-profile family/API checks), `toc_check.lua` (TOC path casing, duplicates, module coverage), `run.sh` (runs both plus `luac5.1` and `luacheck`). `.luacheckrc` configures luacheck: WoW API globals and callback-signature arguments ignored, `Libs/`/`docs/` excluded.
- `docs/swedge/SwedgeTimer_TBC` and `..._Forever`: separate archived addons (BCC 2.5 and Forever/Project Epoch, Interface `20506`). They are not part of the shipped addon and have their own tocs; repo-wide searches will return duplicates. Do not edit them for WotLK fixes. The archived `_Forever` build targets the Project Epoch server, not the WoW Forever/Camelot client (Interface 16001) targeted below.
- Workshop coordination: `workshop.md` (map), `CAIRN.md` (disposition), `desks/journal.md` (work journal), `bench/` (shared results, briefs, lessons), `hands-up.md` (escalation ledger) — see "Workshop mechanics" at the end.

## Conventions

- Modules are Lua 5.1 WoW addons: start with `local addon_name, st = ...`, get the addon with `LibStub("AceAddon-3.0"):GetAddon(addon_name)`.
- Expose handlers as `ST:Name` or `ST.CLASS.Name`.
- Events and lib callbacks are dispatched by `ST.callback_event_handler` to `ST[event]`, so handlers must be named exactly after the event/callback.
- AceEvent dispatches handlers as `(event, ...)`. Any handler that forwards to another module must pass the event name along (see the twist CLEU chain); dropping it shifts every argument.
- Add any new addon `.lua`/`.xml` file to every load-order TOC (base + all flavor variants) in dependency order (libs first); toc paths use backslashes. The only intended divergence between flavor tocs is `_Mainline` omitting `LibClassicSwingTimerAPI`.
- Keep vendored `Libs/` untouched (update from upstream rather than patching locally); `LibClassicSwingTimerAPI` is the swing-engine dependency (classic-line clients only).
- Update `## Version` in every toc variant and `main.lua` (`version`) when releasing.
- Class modules must be listed in every flavor toc or they will not load on that client.

## Gotchas

- `tests/` covers family detection, spell-id resolution and TOC integrity offline; startup in game remains the only real check for WoW-API behaviour. Guard against nil globals and WoW API ordering.
- TOC path casing matters. A historic `AceEVent-3.0.xml` typo was tolerated by Windows clients but fails on case-sensitive loaders; keep path casing exactly matching the files.
- `config_presets.lua` must define `ST.<CLASS>.defaults` before `config.lua` assembles `ST.defaults`.
- SavedVariables key is `SwedgeTimerDB`; profile data lives under `db.profile[CLASS][hand]`.

## Cross-engine (universal single build)

- Goal: one addon build runs on every WoW engine family with no per-client download. Do not create client-specific file trees; the only per-flavor artifacts are the toc variants (which files load), everything else branches in Lua at runtime. Target matrix: Classic Era / SoD 1.15.9 → `_Vanilla` (11509); TBC Anniversary 2.5.6 → `_TBC` (20506); WotLK Titanforge 3.80.2 → `_Wrath` (38002); Retail 12.1.x (12.1.0/12.1.5) and WoW Forever 1.60.1 → `_Mainline` (120100, 120105, 16001); the base `SwedgeTimer.toc` is the classic-line fallback (11509, 20506, 38002) — it ships `LibClassicSwingTimerAPI`, whose file-scope combat-log `RegisterEvent` throws on mainline-code clients, so it must not advertise a mainline interface (audit F6, 2026-10-19).
- `## Interface` can be a comma-separated list of target Interface numbers; supported references and game-type gating live in `/home/sam/wow-ui-source` (see SKILL.md § 10).
- Detect family/API with `WOW_PROJECT_ID` constants — including `WOW_PROJECT_CAMELOT` = 18 on WoW Forever — and feature probes (`C_Spell`, `C_Container`, `C_ClassTalents`, `UnitClass` return arity) rather than hard-coded version strings.
- Mainline-code clients (Retail, WoW Forever) have no classic combat log. WoW Forever instead exposes the native `PLAYER_SWING` event family: `swing_source.lua` provides a `LibClassicSwingTimerAPI`-compatible engine there (Forever only, probe-gated via `C_EventUtils.IsEventValid`). Retail keeps the inert stand-in: `_Mainline.toc` ships no `LibClassicSwingTimerAPI`, and `main.lua` substitutes the stand-in so `init_libs`/options/range/GCD stay alive and the user gets a one-time notice. `main.lua` also arms a 5s post-init deadline: if a library never reports ready (e.g. `LibRangeCheck` on an incompatible client), init proceeds anyway with that feature disabled for the session and a one-time notice.
- `LibClassicSwingTimerAPI` only initializes spell tables for Classic/BCC/Wrath (plus its own Retail path); Cata, Mists, and other families leave tables like `reset_swing_spells` nil, causing indexing errors — do not ship the lib to those flavors until that is fixed.
- API shims implemented in `compat.lua`: classic `GetSpellInfo`/`GetSpellCooldown`/`GetSpellPowerCost` vs `C_Spell.*`; classic `GetTalentInfo`/`GetActiveTalentGroup` vs `C_SpecializationInfo`; `PLAYER_TARGET_SET_ATTACKING` registration gated via `C_EventUtils.IsEventValid` (it does not exist on Mainline). Still to watch: secret-value restrictions in Midnight. When `WOW_PROJECT_ID` is missing, `compat.lua` maps interface `>= 16000` (WoW Forever 1.60.x) to `FOREVER` before the `major == 1` bucket can mislabel it as Era.
- Taint rules still apply, especially show/hide and secure calls during combat; bars are non-secure frames but keep frame strata/parent changes out of combat.
- Seal twisting (paladin): `classes/paladin.lua` owns the twist state machine; `main.lua` registers `COMBAT_LOG_EVENT_UNFILTERED` only for paladins on non-mainline clients. `bars.lua` dispatches a generic per-frame class hook `on_bar_update(self, hand)` (used for the twist window band + success text). Twist lag calibration uses the class keys `lag_multiplier`/`lag_offset` applied to raw world latency — do not also apply the deadzone calibration. Keep `twist.lua` WoW-free; `tests/twist_state.lua` and the smoke CLEU block pin the behaviour.
- Spell weaving (shaman): `classes/shaman.lua` drives the breakpoint marker + cast spark from `weave.lua` math and the swing state; `main.lua` registers the player spellcast lifecycle events and dispatches them to a generic class hook `on_spellcast_event(self, event, unit, cast_guid, spell_id)` (existing `on_spellcast_succeeded` keeps its own hook). Do NOT gate shaman weave visuals on `st.is_mainline` — the Forever client is Mainline-code but must weave; gate on swing activity instead.
- Next action guide (paladin): the pure decision model lives in `nextaction.lua`, the frame in `nextaction_ui.lua`; `classes/paladin.lua` gathers the inputs and drives it from `on_bar_update` before the twist-only gates, so it also runs on the Forever client. Do NOT gate the guide on `st.is_mainline` — swing activity decides (the Retail stand-in never reports a swing, so it stays hidden there).
- Timing clock: all code added after P9 uses the aligned high-precision clock `st.api.get_time()` (GetTimePreciseSec converted once into the GetTime() domain; GetTime() only as fallback). Raw `GetTimePreciseSec()` must never leave compat — bars.lua compares against `GetTime()`.
- Reference repo `/home/sam/wow-ui-source` has branches per client (`live`, `classic`, `classic_era`, `classic_anniversary`, `classic_titan`, `origin/forever`, etc.). Inspect API differences with `git -C /home/sam/wow-ui-source show <branch>:path/to/file` or branch diffs. Checked-out branch is `classic_era` (1.15.9). Read-only agents (hunter/proctor/any other) have no shell: for that tree they must use `ast_grep_search` (works on external paths) rather than `read`/`grep` (blocked there) — see the read-only agents note below.

## Workshop mechanics (CAIRN / desks / bench)

- The repo runs as a workshop under `CAIRN.md` (operating disposition). `desks/journal.md` is the single work journal — status, decisions, lane table; `bench/` is the shared results workspace. Read both before any dispatch or edit.
- The orchestrator updates the journal on dispatch and reconcile. Lane rows record the session id exactly as returned by the dispatch — never beforehand, never invented.
- Desk outputs land in `bench/` as dated, named files (`bench/verify_bank.md`, `bench/discover_features.md`). Never overwrite an existing bench file — append or supersede with a pointer. Reports cite URLs and mark unconfirmed items UNCONFIRMED.
- A brief may only reference files verified to exist on disk at write time. Verify every path and id before dispatching.
- Standing desk rules (in addition to the global ones): no git; no lint-config changes; warning wiring per wire-not-strip (trace to purpose → WIRE properly / REMOVE only if purposeless with rationale / never silence with `_`); preserve file line endings; new user-visible toggles ship nil-safe (`== false` hides, nil = off) with defaults documented for the options pass; new offline checks get mutation proofs on `/tmp/opencode` copies.
- Dispatch briefs live in `bench/briefs/` (verified on disk before dispatch; superseded briefs are marked, not overwritten); earned lessons are recorded in `bench/lessons.md`. Open disagreements become rows in `hands-up.md`; the operator rules, the verdict is written back, the row closes.
- Research agents read the journal + bench first (journals before artifacts), then search for NEW material only — no re-searching answered questions; extend the corpus or supersede it loudly.
- SearxNG MCP (4 tools, operator-hosted): `searxng_web_search` (web search, title/URL/snippet), `web_url_read` (fetch URL → markdown), `searxng_search_suggestions` (query refinement), `searxng_instance_info` (instance capabilities). Research lanes enumerate BOTH catalogs (`search("firecrawl")` + `search("searxng")`, or `firecrawl_find_tools`) and pick per job; `extract`-style structured pulls and SearxNG-backed searches preferred over bare scraping.
- Desks carry state in their own journal (`desks/<name>/journal.md`, per `desk-journal` format: worked on / current state / next step) and emit structured signals (`desks/<name>/.signals/<timestamp>.json`, per `signal-write`: escalation/done/checkpoint + journal marker). The orchestrator's central lane ledger is `desks/journal.md`.

## Research tooling (Firecrawl + SearxNG)

- Firecrawl (:3002) and SearxNG (:8069) run locally in Docker. The Firecrawl MCP catalog exposes 28 tools. Enumerate first (tool search `firecrawl` in Code Mode, or `firecrawl_find_tools`) and pick per job — not just search+scrape:
  - discovery/answers: `firecrawl_search` (categories: developer / research / gov), `firecrawl_gov_search`, `firecrawl_developer_search` (repos/code), `firecrawl_agent` + `firecrawl_agent_status` (multi-source research when URLs are unknown), `firecrawl_research_search_papers` / `_related_papers` / `_read_paper` / `_inspect_paper` (arXiv/literature).
  - single pages: `firecrawl_scrape` (one URL, markdown/HTML/JSON schema), `firecrawl_parse` (structured extraction from documents), `firecrawl_map` (URL discovery on a site), `firecrawl_crawl` + `firecrawl_check_crawl_status` (multi-page).
  - live browser: `firecrawl_interact` / `firecrawl_interact_stop`; monitoring: `firecrawl_monitor_*`; account: `firecrawl_credit_usage`; feedback: `firecrawl_feedback` / `firecrawl_search_feedback`.
- Keep request bodies small; invalid request bodies are why earlier agents fell back to websearch.
- Spell-data lookups: https://wago.tools/ and https://classic.warcraftdb.com/data/spell/<id> (operator-provided; warcraftdb confirmed Molten Blast 425339 + Lava Lash 408507 where wowhead was bot-walled). Cite URL + what the page actually showed.
- wow.export (Classic 1.15 client, CSV, enUS): Spell, SpellIcon, SpellCastTimes, SpellDuration, SpellRange, SpellRadius, SpellEffect, SpellCategory (SINGULAR — plural is modern-only), SpellTotems, TotemCategory, SpellShapeshift, SpellLevels, Talent, TalentTab, SkillLine, SkillLineAbility, Item, GlyphProperties. NOT in 1.15: SpellAuraNames (= Spell names), SpellChain (ranks by name), ShapeshiftForm (it's SpellShapeshift).

## Lane skills (run them on every dispatch)

@hunter note: the hunter agent is extremely good at finding small errors normal review misses — but it has no write/file tools, so dispatch it READ-ONLY and track it yourself: journal the dispatch, file its returned report as its desk journal + done signal, and reconcile its findings into follow-ups.

@read-only agents note (hunter, proctor, and any other read-only agent): they CAN search outside this project with `ast_grep_search` (the `ast_grep_search` tool), and it works flawlessly on `/home/sam/wow-ui-source` — verified: a pattern sweep over that tree returned 51 matches across 20 files, while `read`/`grep` against the same path are blocked (`permission.rejected: external_directory`). So when a read-only lane must check a client API, a Blizzard constant, or any other file outside the repo, it should use `ast_grep_search` with `paths: ["/home/sam/wow-ui-source/Interface", ...]` and `lang: "lua"`, NOT `read`/`grep`. A report that says "the reference repo is not readable" is a tool-choice mistake, not a fact — re-dispatch that check with ast-grep. For a **specific file** outside the repo, `ast_grep_search` over its parent directory still works (it is not path-restricted the way read/grep are). Note ast-grep sees the **checked-out branch** of that repo (`classic_era` right now) — for another branch, the orchestrator (which has shell access) runs `git -C /home/sam/wow-ui-source show <branch>:path` and hands the citation over.

@read-only agents note (missing knowledge): a read-only agent will hit knowledge or tooling it does not have — a branch it cannot check, a client API it cannot find, a runtime it cannot observe, a file it cannot read. It must then **name the gap explicitly** in its report: what it could not determine, what it tried, and what evidence would close it (the exact file/branch/line or the in-client observation). Never paper over a gap with a plausible answer, and never let "I could not check it" pass as "it is fine" — an unverified area is reported as UNVERIFIED, and the orchestrator closes it (shell access for the other branches, a general lane for code, or the operator's in-client session). A missing-knowledge list is a deliverable, not a failure.

@bench-read — read the trail before you work: journals first, then artifacts, bench/lessons.md included.
Do not re-search answered questions; do not re-learn earned lessons.

@desk-open — sit at the desk named in your dispatch: read desks/<name>/journal.md first, work at that desk only.
Do not work outside it or overwrite it.

@desk-journal — leave the trail in desks/<name>/journal.md: what you did, current state, next step.
Do not go silent; do not bluff.

@signal-write — report state changes into desks/<name>/.signals/ as done, checkpoint, blocked, hands-up.
Do not sit on a disagreement the operator must rule; put it in hands-up.md.

Map, disposition, escalation ledger, central ledger: @workshop.md, @CAIRN.md, @hands-up.md, desks/journal.md.

Orchestrator keeps hands-up.md in sync with desks and bench: lane hands-up signals and journal disagreements become open rows with evidence links; operator verdicts get written back and rows move to resolved. CAIRN.md changes only on operator order.

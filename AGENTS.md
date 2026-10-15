# SwedgeTimer

WoW addon (Lua) shipping one universal build for WotLK Classic and the other classic-line and Mainline clients (see the Cross-engine section for the target matrix). Vendored Ace3 and other libs. There is no build step; offline checks live in `tests/` (`bash tests/run.sh`), and the real check for API behaviour is loading the addon in a client.

## Layout

- Active addon is the repo root; `SwedgeTimer.toc` (base) plus the flavor variants (`SwedgeTimer_Vanilla/_TBC/_Wrath/_Mainline/_Cata/_Mists.toc`) are the authoritative load orders. The client picks one by flavor dispatch: game-type suffix > family suffix > base.
- `main.lua`: addon object, WoW/lib event wiring, swing-timer/range/GCD orchestration.
- `bars.lua`: frame construction, layout, `OnUpdate`, textures/texts.
- `config_presets.lua`: AceDB defaults (`ST.class_defaults`, `ST.bar_defaults`, per-class `ST.<CLASS>.defaults`).
- `config.lua`: wraps the above into `ST.defaults`.
- `option_tables.lua` + `option_table_presets.lua`: AceConfig settings UI.
- `classes/{druid,hunter,paladin,shaman,warrior}.lua`: class-specific colors/procs; only these five classes have logic.
- `utils.lua`, `LibLatencyMonitor.lua`, `LibGlobalCooldown.lua`: helpers.
- `twist.lua`: pure paladin seal-twisting logic (twist window, attempt/success detection, impossible-twist heuristic). WoW-free by design; unit-tested by `tests/twist_state.lua`.
- `weave.lua`: pure shaman spell-weaving math (breakpoint marker fraction, clip/safe-window math, haste/Maelstrom cast-time model). WoW-free by design; unit-tested by `tests/weave_state.lua`.
- `swing_source.lua`: the WoW Forever swing engine (native `PLAYER_SWING`), mirroring the `LibClassicSwingTimerAPI` callback surface so `main.lua` runs unchanged there; inert on every other family.
- `compat.lua`: the single cross-client layer — family detection (`st.family`, `st.is_retail`, `st.is_mainline`), normalized `st.api.*` wrappers, `st.gcd_probe_spell_id`. Never call a cross-client API directly elsewhere; go through `st.api`.
- `tests/`: offline verification — `smoke.lua` (client-profile family/API checks), `toc_check.lua` (TOC path casing, duplicates, module coverage), `run.sh` (runs both plus `luac5.1` and `luacheck`). `.luacheckrc` configures luacheck: WoW API globals and callback-signature arguments ignored, `Libs/`/`docs/` excluded.
- `docs/swedge/SwedgeTimer_TBC` and `..._Forever`: separate archived addons (BCC 2.5 and Forever/Project Epoch, Interface `20506`). They are not part of the shipped addon and have their own tocs; repo-wide searches will return duplicates. Do not edit them for WotLK fixes. The archived `_Forever` build targets the Project Epoch server, not the WoW Forever/Camelot client (Interface 16001) targeted below.

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

- Goal: one addon build runs on every WoW engine family with no per-client download. Do not create client-specific file trees; the only per-flavor artifacts are the toc variants (which files load), everything else branches in Lua at runtime. Target matrix: Classic Era 1.15.9 → `_Vanilla` (11509); TBC Anniversary 2.5.6 → `_TBC` (20506); WotLK Classic 3.4.1 → base (30401); Titanforge 3.80.2 → `_Wrath` (30401, 38002); Retail 12.1.0 and WoW Forever 1.60.1 → `_Mainline` (120100, 120105, 16001).
- `## Interface` can be a comma-separated list of target Interface numbers; supported references and game-type gating live in `/home/sam/wow-ui-source` (see SKILL.md § 10).
- Detect family/API with `WOW_PROJECT_ID` constants — including `WOW_PROJECT_CAMELOT` = 18 on WoW Forever — and feature probes (`C_Spell`, `C_Container`, `C_ClassTalents`, `UnitClass` return arity) rather than hard-coded version strings.
- Mainline-code clients (Retail, WoW Forever) have no classic combat log. WoW Forever instead exposes the native `PLAYER_SWING` event family: `swing_source.lua` provides a `LibClassicSwingTimerAPI`-compatible engine there (Forever only, probe-gated via `C_EventUtils.IsEventValid`). Retail keeps the inert stand-in: `_Mainline.toc` ships no `LibClassicSwingTimerAPI`, and `main.lua` substitutes the stand-in so `init_libs`/options/range/GCD stay alive and the user gets a one-time notice. `main.lua` also arms a 5s post-init deadline: if a library never reports ready (e.g. `LibRangeCheck` on an incompatible client), init proceeds anyway with that feature disabled for the session and a one-time notice.
- `LibClassicSwingTimerAPI` only initializes spell tables for Classic/BCC/Wrath (plus its own Retail path); Cata, Mists, and other families leave tables like `reset_swing_spells` nil, causing indexing errors — do not ship the lib to those flavors until that is fixed.
- API shims implemented in `compat.lua`: classic `GetSpellInfo`/`GetSpellCooldown`/`GetSpellPowerCost` vs `C_Spell.*`; classic `GetTalentInfo`/`GetActiveTalentGroup` vs `C_SpecializationInfo`; `PLAYER_TARGET_SET_ATTACKING` registration gated via `C_EventUtils.IsEventValid` (it does not exist on Mainline). Still to watch: secret-value restrictions in Midnight. When `WOW_PROJECT_ID` is missing, `compat.lua` maps interface `>= 16000` (WoW Forever 1.60.x) to `FOREVER` before the `major == 1` bucket can mislabel it as Era.
- Taint rules still apply, especially show/hide and secure calls during combat; bars are non-secure frames but keep frame strata/parent changes out of combat.
- Seal twisting (paladin): `classes/paladin.lua` owns the twist state machine; `main.lua` registers `COMBAT_LOG_EVENT_UNFILTERED` only for paladins on non-mainline clients. `bars.lua` dispatches a generic per-frame class hook `on_bar_update(self, hand)` (used for the twist window band + success text). Twist lag calibration uses the class keys `lag_multiplier`/`lag_offset` applied to raw world latency — do not also apply the deadzone calibration. Keep `twist.lua` WoW-free; `tests/twist_state.lua` and the smoke CLEU block pin the behaviour.
- Spell weaving (shaman): `classes/shaman.lua` drives the breakpoint marker + cast spark from `weave.lua` math and the swing state; `main.lua` registers the player spellcast lifecycle events and dispatches them to a generic class hook `on_spellcast_event(self, event, unit, cast_guid, spell_id)` (existing `on_spellcast_succeeded` keeps its own hook). Do NOT gate shaman weave visuals on `st.is_mainline` — the Forever client is Mainline-code but must weave; gate on swing activity instead.
- Timing clock: all code added after P9 uses the aligned high-precision clock `st.api.get_time()` (GetTimePreciseSec converted once into the GetTime() domain; GetTime() only as fallback). Raw `GetTimePreciseSec()` must never leave compat — bars.lua compares against `GetTime()`.
- Reference repo `/home/sam/wow-ui-source` has branches per client (`live`, `classic`, `classic_era`, `classic_anniversary`, `classic_titan`, `origin/forever`, etc.). Inspect API differences with `git -C /home/sam/wow-ui-source show <branch>:path/to/file` or branch diffs. Checked-out branch is `classic_era` (1.15.9).

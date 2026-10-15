# SwedgeTimer

WoW addon (Lua) for WotLK Classic (Interface `30401`), with vendored Ace3 and other libs. There is no build/test/lint tooling; verification means loading the addon in a WotLK client.

## Layout

- Active addon is the repo root; `SwedgeTimer.toc` is the authoritative load order.
- `main.lua`: addon object, WoW/lib event wiring, swing-timer/range/GCD orchestration.
- `bars.lua`: frame construction, layout, `OnUpdate`, textures/texts.
- `config_presets.lua`: AceDB defaults (`ST.class_defaults`, `ST.bar_defaults`, per-class `ST.<CLASS>.defaults`).
- `config.lua`: wraps the above into `ST.defaults`.
- `option_tables.lua` + `option_table_presets.lua`: AceConfig settings UI.
- `classes/{druid,hunter,paladin,warrior}.lua`: class-specific colors/procs; only these four classes have logic.
- `utils.lua`, `LibLatencyMonitor.lua`, `LibGlobalCooldown.lua`: helpers.
- `docs/swedge/SwedgeTimer_TBC` and `..._Forever`: separate archived addons (BCC 2.5 and Forever/Project Epoch, Interface `20506`). They are not part of the WotLK addon and have their own tocs; repo-wide searches will return duplicates. Do not edit them for WotLK fixes.

## Conventions

- Modules are Lua 5.1 WoW addons: start with `local addon_name, st = ...`, get the addon with `LibStub("AceAddon-3.0"):GetAddon(addon_name)`.
- Expose handlers as `ST:Name` or `ST.CLASS.Name`.
- Events and lib callbacks are dispatched by `ST.callback_event_handler` to `ST[event]`, so handlers must be named exactly after the event/callback.
- Add any new `.lua`/`.xml` file to `SwedgeTimer.toc` in dependency order (libs first); toc paths use backslashes.
- Keep vendored `Libs/` untouched; `LibClassicSwingTimerAPI` is the swing-engine dependency.
- Update both `SwedgeTimer.toc` (`## Version`) and `main.lua` (`version`) when releasing.
- Class modules must be listed in the toc or they will not load.

## Gotchas

- There are no automated tests; the only real check is startup in game. Guard against nil globals and WoW API ordering.
- `SwedgeTimer.toc` line 28 has a case typo: `Libs\AceEvent-3.0\AceEVent-3.0.xml` vs the actual file `AceEvent-3.0.xml`. Windows clients are case-insensitive, but case-sensitive loaders can fail to load AceEvent.
- `ST:UPDATE_SHAPESHIFT_FORM` checks `self.class`, which is never set, so the handler currently early-returns; form visibility updates in practice come from settings and talent events.
- `config_presets.lua` must define `ST.<CLASS>.defaults` before `config.lua` assembles `ST.defaults`.
- SavedVariables key is `SwedgeTimerDB`; profile data lives under `db.profile[CLASS][hand]`.

## Cross-engine (universal single build)

- Goal: one addon build runs on every WoW engine family (Classic Era/Anniversary, TBC, Wrath, Cata, Mists, Retail) with no per-client download. Do not create client-specific file trees or per-client tocs; branch in Lua by runtime detection.
- `## Interface` can be a comma-separated list of target Interface numbers; supported references and game-type gating live in `/home/sam/wow-ui-source` (see SKILL.md § 10).
- Detect family/API with `WOW_PROJECT_ID` constants and feature probes (`C_Spell`, `C_Container`, `C_ClassTalents`, `UnitClass` return arity) rather than hard-coded version strings.
- Swing tracking dependency `LibClassicSwingTimerAPI` already branches by family; it still uses `COMBAT_LOG_EVENT_UNFILTERED`, which is removed in Retail 12.0. Any Retail support must replace swing detection, not only widen the toc.
- `LibClassicSwingTimerAPI` only initializes spell tables for Classic/BCC/Wrath/Retail; Cata, Mists, and other families leave tables like `reset_swing_spells` nil, causing indexing errors.
- API shims needed: classic `GetSpellInfo` vs retail `C_Spell.GetSpellInfo`; classic `GetTalentInfo` vs `C_ClassTalents`; classic-era saved-variable/state behavior; secret-value restrictions in Midnight.
- Taint rules still apply, especially show/hide and secure calls during combat; bars are non-secure frames but keep frame strata/parent changes out of combat.
- Reference repo `/home/sam/wow-ui-source` has branches per client (`live`, `classic`, `classic_era`, `classic_anniversary`, etc.). Inspect API differences with `git -C /home/sam/wow-ui-source show <branch>:path/to/file` or branch diffs. Checked-out branch is `classic_era` (1.15.9).

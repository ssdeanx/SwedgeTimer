# Brief — HUD secret-safe cooldown/GCD implementation (2026-11-08)

## Role and mode

Implementer lane for the Lead's Agent Team. You own the files below and no others.
Write code, red-first tests, mutation proofs, one bench report, one desk journal,
and one done signal.

## Mission

On **WoW Forever only**, make the Cooldown HUD fully work with ability cooldowns,
countdown text, and the global cooldown while the client's cooldown data is secret
(combat, encounter, challenge mode, PvP, addon-restricted maps), without ever
letting a secret value enter tainted addon logic or a cache. On every other
client, behaviour must remain byte-identical in effect.

The operator's words: "make sure that everything that is secret in wow forever,
is correctly passed the data so it does not become tainted. especially if
something is cached, that will cause problems because data cant be tainted and it
will be without a check for it." "I want you to try and get it fully working with
global cooldown, and cooldowns in combat/dungeons." "Do not break any other
clients. Enterprise grade quality."

## Required reading, in order

1. `bench/forever_hud_api_2026-11-08.md` — the research lane's contract. If it is
   absent or inconclusive, stop and report; do not guess the API.
2. `hud.lua` header (frozen slot/provider contract, lines 1-120) and the current
   paint path (`HUD.paint`, `HUD.update_display`, `HUD.on_update`).
3. `compat.lua` cooldown/aura/secret helpers (search
   `GetSpellCooldown`, `get_cooldown_remaining`, `is_secret`, `UnitAura`).
4. `LibGlobalCooldown.lua`.
5. `bench/secret_consumers_audit_2026-11-06.md`,
   `bench/secret_core_fix_2026-11-06.md`,
   `bench/secret_guide_fix_2026-11-06.md`,
   `bench/secret_hud_fix_2026-11-06.md`,
   `bench/forever_toc_range_power_2026-11-07.md`.
6. `AGENTS.md` (Cross-engine, Gotchas, Workshop mechanics), `desks/journal.md`
   tail, `bench/lessons.md`.

## Write scope (exact)

- `hud.lua`
- `compat.lua` (additive helpers only; do not change an existing wrapper contract)
- `LibGlobalCooldown.lua`
- `tests/hud_state.lua`
- `tests/forever_secret_compat_state.lua`
- `bench/hud_forever_cooldown_2026-11-08.md`
- `desks/hud-cooldown-fix/**`

`tests/secret_guard_state.lua` is **cross-lane**: only touch it with explicit Lead
approval for an intentional pin re-cut, and report the exact pins. Do **not**
touch `hud.lua`-adjacent config/options/TOC/main/bars/class modules/docs; those
are other lanes or out of scope. No git, no version fields.

## Work items

### 1. Cooldown swipe pass-through

Using the T1 verdict, implement the sanctioned Forever path:

- Prefer `C_Spell.GetSpellCooldownDuration(spell, ignoreGCD)` (or the exact API
  the T1 report proves) and pass the returned **opaque duration object** to the
  icon's CooldownFrame through the documented sink
  (`SetCooldownFromDurationObject` / the exact permitted call). Do not read
  `GetRemainingDuration`/`GetTotalDuration`/`GetStartTime` when
  `HasSecretValues()` is true.
- When the duration object is plain (`HasSecretValues()` false), the existing
  numeric path may keep its exact look; decide one way and pin it.
- Keep the current readable-cooldown behaviour for non-Forever clients
  untouched: same `GetSpellCooldown` path, same swipe/text/tints.
- A restricted numeric read must still be the documented unknown face **unless**
  the native pass-through object is available; then the icon shows the real
  native swipe and must not be painted as a fabricated full/ready state.
- Trinket slots: follow the T1 item verdict. If no duration-object path exists,
  preserve the SEC-10 tri-state and the existing restricted grey face; do not
  invent an item timing.

### 2. Countdown text

- Use the sanctioned Forever text path from T1 (native CooldownFrame countdown
  numbers and/or `C_DurationUtil.CreateDurationTextBinding`) for restricted
  cooldowns. Never format, round, compare or concatenate a secret number.
- Preserve the 2 s GCD text suppression rule. If the native path cannot express
  it, configure `SetMinimumCountdownDuration` (or the exact permitted equivalent)
  and pin the rule in tests; do not simply drop the rule silently.
- Readable cooldowns keep the existing custom text, colours, 0.1 s precision and
  hide-on-GCD behaviour.

### 3. Global cooldown

- Implement the GCD strategy from T1 so a running GCD paints on the active
  ability icon(s) during combat/instances without reading restricted numbers.
- Primary candidate: the per-spell duration object with `ignoreGCD = false`;
  the GCD is then carried by the same native pass-through. Verify against the
  T1 report before coding.
- `LibGlobalCooldown` may keep `calculate_expected_spell_gcd`,
  `SPELL_UPDATE_COOLDOWN`, cast events and the plain-value cache; on a
  restricted read it must clear/skip the timing cache rather than store a
  partial number. Pin this with a secret-sentinel test.
- Do not gate any GCD fix on `st.is_mainline` alone; gate on Forever + the API
  probe, exactly like the T1 verdict says.

### 4. Secret/cache hygiene (the operator's specific worry)

Audit and fix, in your scope:

- `HUD.known_names` (spell id -> name cache), `known_cache` (TTL knowledge
  cache), `HUD.layout_cache`, `HUD.icons[i]` state fields, `HUD.trinkets[13/14]`,
  `TRINKET_STATE`, `PREVIEW_STATE`.
- `LibGlobalCooldown` state (`gcd_duration`, `gcd_started`, `gcd_expires`,
  `current_spell_gcd`, `current_spell_haste`).
- `compat.api.GetSpellCooldown` / `get_cooldown_remaining` /
  `GetInventoryItemCooldown` / `GetSpellInfo` / `IsSpellUsable` / aura readers.

Rules:

- No secret value may be stored in a plain table (as key or value), a string, a
  comparison, arithmetic, a formatter or a table index.
- A cached entry must be proven plain before it is read, or dropped/revalidated.
  Do not rely on a flag written on a previous tick to prove today's value.
- If a table can receive a secret key, use the client's documented pattern from
  T1 (`settablesecurity`/`scrub`/`secretwrap`/`secretunwrap` as actually
  permitted for addons) or refuse the write.
- Add a defence-in-depth guard at the paint boundary for boolean fields too
  (`usable`, `in_range`, `glow`), not only numeric fields: a secret boolean must
  land on the unknown/no-tint face, never reach `== false`.
- Cache tests must inject `issecretvalue` sentinels into the cache-producing
  read and prove the cache does not retain them and a later tick cannot consume
  them unchecked.

### 5. Tests (red-first, mutation-proven)

Extend `tests/hud_state.lua` and `tests/forever_secret_compat_state.lua`.
Required legs, at minimum:

- Forever restricted ability cooldown: native duration-object sink is called, no
  secret number is read, the icon is not painted as ready/full, the text follows
  the native path.
- Forever plain cooldown: existing numeric path and exact visuals unchanged.
- Forever GCD: native swipe (and the 2 s text rule) with no restricted-number
  read; exact start/end observation pinned through the stub.
- Non-Forever: zero calls to the duration-object API; exact old `SetCooldown`
  sequence preserved.
- Cache: `known_names` never stores a secret name; `known_cache` never stores a
  secret boolean; `HUD.icons`/`HUD.trinkets`/`LibGlobalCooldown` never retain a
  secret; a poisoned provider state field is rejected at paint.
- Trinket: SEC-10 tri-state still hides only a confirmed passive; restricted
  stays visible on the unknown face.
- Missing-API clients: no Forever API present -> silent fallback, no throw.

Run the **full** `bash tests/run.sh` after the change, not only the touched
suites; report the exact step/failed count and any pre-existing failure with its
cause. Run `luacheck` on touched files and record the tree floor. Run
`luac5.1 -p` on every changed Lua file. Preserve LF line endings.

Mutation proofs: copy the addon to an isolated `/tmp` directory, apply at least
three single-line reversions of the new guards (e.g., remove the duration-object
path, let a restricted read paint as ready, let a secret value enter a cache),
run the relevant suites and record the exact failure counts and exit codes.
Restore the copies; never mutate the real tree.

## Deliverable

`bench/hud_forever_cooldown_2026-11-08.md` with:

1. What changed, file by file, with line references.
2. The exact Forever path chosen (read API -> sink -> text -> cache) and the T1
   citations used.
3. Cache hazard matrix (before -> after) for every cache in scope.
4. Test evidence: suite counts, full harness step/fail, luacheck, luac.
5. Mutation table: mutant, expected failure, actual failure count, exit code.
6. UNCONFIRMED in-client items and the exact `/run` probes to close them.

Also `desks/hud-cooldown-fix/journal.md` + `.signals/<timestamp>.json`.

## Hard constraints

- **WoW Forever only.** Every new branch is gated on
  `st.family == "FOREVER"` **and** an exact API probe; all other clients keep the
  existing code path. No `st.is_mainline`-only gate.
- Never read, compare, format, concatenate or cache a secret value.
- No git, no version bump, no TOC/config/options/main/bars/class/docs edits.
- Do not guess: if T1 contradicts this brief, follow T1's evidence and report
  the deviation.
- Enterprise-grade: exact evidence, mutation proofs, no vacuous tests, no `_`
  silencing, no lint-config changes.

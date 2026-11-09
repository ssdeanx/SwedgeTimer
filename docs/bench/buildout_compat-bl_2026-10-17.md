# buildout compat-bl — 2026-10-17 (round 1)

Desk compat-bl, brief `bench/briefs/brief_compat-bl_2026-10-17.md`. Scope held:
`compat.lua` + `tests/smoke.lua` only. No git. No lint-config changes. No `_`
renames, no unused-variable work. Endings preserved (LF, verified with `file`).
Nothing committed; all changes sit in the tree.

## 1. Changes

### compat.lua (4 in-place insertions, existing lines untouched)
1. **Header doc lines** for `st.lust_spell_ids` / `st.lust_supported` (Sets block).
2. **New section "Bloodlust / Heroism (the lust window)"** after the GCD probe block:
   - `st.lust_spell_ids = { 2825, 32182 }` — CONFIRMED per `bench/verify_bank.md` §2
     (Wowhead TBC pages: Bloodlust 2825 / Horde, Heroism 32182 / Alliance, 40s).
   - `st.lust_supported = (family ~= "ERA" and family ~= "UNKNOWN")` — the Era gate,
     family-derived (WOW_PROJECT_ID / interface-bucket detection, never version
     strings). Era: closed (Bloodlust/Heroism is TBC+ only, verify_bank §2
     NOT-APPLICABLE row). UNKNOWN: closed (no confirmed family → conservative off;
     arms only on TBC/WRATH/CATA/MISTS/RETAIL/FOREVER).
   - `st.post_lust_debuff_ids = { 57723, 57724 }` — registered **UNCONFIRMED** with
     the in-client check note; nothing hard-depends on them.
3. **`api.scan_player_aura(predicate)`** directly under the aura wrappers:
   stateless single pass over `api.UnitAura("player", i, "HELPFUL")`, `1..40`,
   `remaining = expirationTime - api.get_time()` clamped ≥ 0, `stacks` normalized
   (count > 1 → count, otherwise nil). Runs through the file's own wrappers on
   every family: classic global (Era/TBC/Wrath) and C_UnitAuras (Retail, Forever).

### tests/smoke.lua (+21 checks, 109 → 130)
Group "Lust window (C2)" after the profile-family blocks: Era/UNKNOWN gate closed,
TBC/Wrath/Forever armed, exact id lists (and the lust list carries nothing
unconfirmed), TBC classic-path math (`1030-1000 → 30`), no-expiration → nil,
stacks rules (5 → 5, nil/1 → nil), unmatched id → nil,nil, nil predicate →
nil,nil, predicate receives `(spell_id, name, stacks)` and the scan stops at the
first nil entry, stale expiration clamps to 0, and the Retail C_ path through a
C_UnitAuras.GetAuraDataByIndex stub.

## 2. The frozen contract (restated; hunter H2 / paladin P3 code against THIS)

```lua
duration_remaining_seconds, stacks = st.api.scan_player_aura(predicate)
```

| Element | Rule |
|---|---|
| predicate | `predicate(spell_id, name, stacks)` → truthy match; **first match wins**. `spell_id` may be nil on a client without numeric ids — an id equality test is already nil-safe. Predicate errors propagate (no pcall: predicate is addon code, not a cross-client surface). |
| not found / unavailable | `(nil, nil)` — when the aura is absent, no aura API exists on the client, a secret entry degrades absent (whole-or-nothing wrapper), or the predicate is not a function. Treat nil as "no window", never zero. |
| nil remaining + set stacks | found-but-no-time (rare: client reports no expirationTime for that entry). |
| duration_remaining_seconds | from `expirationTime` on the `api.get_time()` axis (the exact domain bars.lua and the deck compare in); `0` once expired; never negative. No `duration`-as-remaining fallback (duration is a total, not a remaining). |
| stacks | `count` for anything above 1; nil for non-stacking auras (classic count nil, retail `applications` 1) — **identical value on every family** for the same aura. |
| filter | `"HELPFUL"` (player-owned and *received* buffs both count — Bloodlust arrive from another player). |
| scan cap | 40 entries; end-of-list is the wrapper's nil entry, same as existing consumers. |
| state | none: one pass per call, re-pollable at any cadence (the TBC consumer's 0.05s poll cadence lives in the calling lane; compat holds no timer state). |

Era gate for BL helpers: `if st.lust_supported then ... end` — on, it is derived
from `st.family`; the ids themselves (`st.lust_spell_ids`) are data and are NOT
probed to decide arming.

## 3. Evidence

- Repo (real tree): `bash tests/run.sh` — **33 steps, 0 failed**; luacheck
  **45 warnings / 0 errors in 68 files** (baseline byte-for-byte unchanged from
  pre-edit; warnings list identical, the "new" notification at compat.lua:34 is
  the pre-existing `addon_name` local after a +2-line shift).
- Focused: `luacheck compat.lua tests/smoke.lua` → 1 warning/0 errors (the same
  pre-existing `addon_name` entry); `lua5.1 tests/smoke.lua` → 130 checks,
  0 failures.
- Mutation proofs on `/tmp/opencode/mut_compat-bl/` (disposable copy):
  1. Baseline on the copy: `bash tests/run.sh` → 33 steps, 0 failed.
  2. **Era-gate broken** (`st.lust_supported = true`): smoke →
     `FAIL era: lust window must not arm on Classic Era` +
     `FAIL unknown family: lust window stays off` (2 failures) — the gate has a
     check pinning it in both directions.
  3. **Nil path broken** (predicate short-circuit `return nil, nil` → `return 0, 0`):
     smoke → `FAIL tbc scan: nil predicate -> nil, nil` (1 failure).
  4. Restore: `diff compat.lua` against the repo file → IDENTICAL; copy suite
     green again (33/33). Mutated files never left the /tmp copy.
- Wiring-check invariants still hold with the new surface (it is statically part
  of the green 33/33): `function api.scan_player_aura(` satisfies the check-4
  assignment pattern, so future `st.api.scan_player_aura` references in
  classes/*.lua will resolve; `api.get_time()` usage keeps the clock rule intact.

## 4. UNCONFIRMED list (explicit, per brief / verify_bank §2)

| Item | Status | Where flagged |
|---|---|---|
| Exhaustion / Sated 57723 / 57724 | **UNCONFIRMED** — no primary source; secondary WeakAura mentions only. The 57723-vs-57724 name mapping is unconfirmed too. | compat.lua comment at `st.post_lust_debuff_ids`; smoke label "registered (UNCONFIRMED...)"; they are NOT in `st.lust_spell_ids` and nothing hard-depends on them. |
| Exhaustion/Sated **in-client check** | OPEN — read the debuff id off the player right after a Bloodlust lands, then confirm or kill the row. | compat.lua comment; this desk journal; §5 below. |
| Era/TBC expirationTime freshness (offline claim) | OFFLINE-VERIFIED ONLY — the smoke stubs control the clock; real client freshness behavior is not claimed beyond the API's documented returns. **Verified offline ≠ verified in-client** per CAIRN. | this report; in-client smoke item in §5. |
| TBC "0.05s player-aura poll" cadence | Interpretation note — the brief's phrase is realized as a stateless scan plus a consumer-side cadence decision; compat ships no poller and no timer. (Honest stop: no primary source was re-researched for a compat-side state claim.) | compat.lua comment; this report. |

## 5. In-client smoke items (offline harness cannot cover these)

1. Load on each family (Era / TBC Anniversary / Titanforge / Forever / Retail):
   `/dump st.lust_supported` — expect false on Era, true elsewhere; UNKNOWN
   legacy clients report false.
2. On a TBC+ client with Bloodlust/Heroism cast on you:
   `/dump select(10, UnitAura("player", ...))`-style scan via a temporary
   predicate confirming id 2825 or 32182 matches and remaining counts down.
3. Read the post-lust debuff id (item above) after Bloodlust expires: confirm or
   kill 57723/57724 before any lane consumes them.
4. Retail/Forever: confirm the C_ path fires with a `C_UnitAuras` payload whose
   `expirationTime` ticks down (secret-regime: restricted entries must degrade to
   not-found, never error).

## 6. Option defaults (for the options pass)

- **No new user-visible toggles were added in this round** — nothing in
  compat.lua/smoke.lua surfaces an option, so no default-visible change exists
  and no nil-safe toggle shipping rule applies. Consumers (hunter H2, paladin P3)
  own their toggles in their lanes; when they arm via `st.lust_supported` there
  is no default-visible change either, because Bloodlust absence degrades to
  "no window" (the off state).
- One implicit non-toggle default worth recording for the options pass:
  `scan_player_aura` caps at 40 entries and always degrades to `(nil, nil)` on
  unknown clients — callers should treat that as "no window", not as an option
  failure, regardless of any future user setting.

## 7. Residual state for the next desk

- Tree differs from pre-dispatch by: compat.lua (+~80 lines), tests/smoke.lua
  (+~115 lines), desks/compat-bl/journal.md, this file,
  desks/compat-bl/.signals/2026-10-17T131622Z.json.
- Hunter/paladin lanes may now consume the frozen contract as written in §2.
- The secret-guard offline suite (`tests/secret_guard_state.lua`) remains green —
  the scan adds no new secret-reading surface beyond the existing aura wrapper.

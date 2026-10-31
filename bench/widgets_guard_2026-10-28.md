# widgets-guard — the sound preview's AceDB `**` trap (F2.5)

- **Desk:** `widgets-guard` · **Lane id:** `ses-88719739-57bc-4627-9554-a35de6bdf4c0`
  (as dispatched in `desks/journal.md`)
- **Date:** 2026-10-28
- **Status:** **DONE (offline)** — no live-client proof; see §7.
- **Scope held:** `widgets.lua` + `tests/rotationtext_state.lua` (the one suite that
  covers `widgets.lua`). Nothing else touched: no `config.lua`, `bars.lua`,
  `tests/bars_state.lua`, `Libs/`, TOCs, docs or lint config. Version stays **2.1.3**.

---

## 1. The defect, confirmed by reading and then reproduced by test

Pre-fix `widgets.lua:40-49` (the two reads were lines 44-46):

```lua
local class_db = ST.player_class and ST.db.profile[ST.player_class]
channel = class_db and class_db.sound_channel
channel = channel or ST.db.profile.sound_channel
```

Both reads are **plain table reads** on AceDB objects, and both objects carry a `'**'`
defaults metatable:

| object | `'**'` default | declared at |
|---|---|---|
| profile root | `ST.class_defaults` | `config.lua:76` |
| every class row | `ST.bar_defaults` | `config_presets.lua:333, 460, 630, 716, 895, 970, 1107, 1283, 1356, 1496` — all ten class blocks, first key |

`Libs/AceDB-3.0/AceDB-3.0.lua:88-107` gives that metatable an `__index` that **CREATES a
defaults-filled table, rawsets it into the host table, and returns it**:

```lua
__index = function(t,k2)
    if k2 == nil then return nil end
    local tbl = {}
    copyDefaults(tbl, v)
    rawset(t, k2, tbl)
    return tbl
end
```

`ST.defaults.profile` has no top-level `sound_channel`, and only `PALADIN.defaults`
ships one (`config_presets.lua:788`). So on nine of ten classes BOTH keys are absent and
both reads answer a truthy **TABLE**, which the old code handed unpcall'd to
`PlaySoundFile`.

**Why it was latent:** the only two consumers of `st.widgets.preview_sound` are the
`Dropdown-SoundPreview` selects `twist_sound_choice` / `twist_success_sound_choice`, and
those live only in the PALADIN options panel (`option_tables.lua:3111-3150`); PALADIN's
class row ships the string, copied as a real leaf by AceDB. Same failure class as the
appearance migration (F2, `config.lua:158-179`), not a live failure.

**One precision correction to the brief's wording** (kept honest, does not change the
fix): the trap that *actually fires* is the **class-row** read. Because it already returns
a table, the `or` short-circuit means `ST.db.profile.sound_channel` is normally never
evaluated by the old code. The profile root is nevertheless a real `'**'` trap — proven
directly by the fixture in §3 — and with the fix a profile-level `sound_channel` becomes
reachable for the first time.

---

## 2. What changed

### `widgets.lua` (210 → 240 lines)

| Req | Change | Where |
|---|---|---|
| W1 | `DEFAULT_SOUND_CHANNEL = "Master"` file-local (the shipped fallback) | `widgets.lua:37-40` |
| W1 | `sound_channel()` now `rawget`s the class row **and** its leaf, then `rawget`s the profile root, requires `type(channel) == "string"`, else returns the shipped default. The class-token read is `rawget(profile, ST.player_class)` (guarded on a string token) so an unlisted token cannot materialise a defaults row either. | `widgets.lua:42-72` |
| W2 | `pcall(play_sound_file, path, sound_channel())`; on failure nothing is latched, so the next hover is a clean attempt | `widgets.lua:171-177` |
| W2 | `pcall(stop_sound, preview_handle)` — stopping a handle the client no longer knows cannot throw out of a list rebuild | `widgets.lua:149-154` |
| W4 | `path` must be a string **or a number** (PlaySoundFile accepts a fileDataID); a corrupt map entry is a silent no-op instead of a bad client call | `widgets.lua:165-169` |

Ancient contract kept: silent no-op when the key/map/`PlaySoundFile` is missing; the
preview handle still stops the previous preview; the map resolution chain is untouched.

**Behaviour deltas, stated:**
- PALADIN (the only reachable class today): **no change** — class row ships `"Master"`,
  a user pick is stored on the class row and still wins.
- Non-paladin previews (currently unreachable): now always safe, and the archive's
  documented profile-level `sound_channel` fallback becomes **live** (previously shadowed
  by the class row's metatable table).
- No new user-visible toggle; nothing to document for the options pass.

### `tests/rotationtext_state.lua` — the suite that covers `widgets.lua`

Verified as the covering suite: it is the only file in `tests/` that reads/pins
`widgets.lua` (`tests/rotationtext_state.lua:410-423`), and no other suite
mentions `preview_sound` or `sound_channel`.

- New **section 7b**, `tests/rotationtext_state.lua:425-692`: loads the **real vendored
  AceDB-3.0**, the **shipped defaults** (`config_presets.lua` + `config.lua`) and the
  **real `widgets.lua`** in a sandbox, boots a real `AceDB:New({}, ST.defaults, true)`
  profile, and drives `st.widgets.preview_sound` plus the widget's own `OnEnter` hook.
  The fixture cannot drift from the client's database shape.
- Header coverage bullet added (`tests/rotationtext_state.lua:16-18`).
- Check count **246 → 286** (+40), all passing.

---

## 3. The proof

### 3a. The fixture is genuinely `'**'`-shaped (asserted, not assumed)

Section 7b asserts, on the booted real profile:

- the profile root's metatable has a function `__index` (`FIXTURE:` check);
- the `WARRIOR` row carries its own metatable;
- `rawget(profile, "sound_channel") == nil` and `rawget(class_row, "sound_channel") == nil`;
- the **defective** plain reads answer a TABLE **and persist it** (`rawget` then sees the
  same table) — on the profile root and on the class row alike.

That is the trap itself, on the shipped object, before the fix is exercised.

### 3b. The fixed behaviour (all green in the suite)

- W1: absent channel → `PlaySoundFile` receives the **string** `"Master"`; neither
  `rawget(profile, "sound_channel")` nor the class row's key exists afterwards (no junk
  written to the saved profile).
- W1: saved precedence — class row (`"Music"`) > profile root (`"SFX"`) > `"Master"`.
- W1: corrupt saved values (a table on the class row, a number on the profile root) →
  `"Master"`; a STRING is the contract, not merely non-nil.
- W1 (real trigger): the registered `Dropdown-SoundPreview` constructor is invoked, its
  `SetList` hook attaches `OnEnter`, and hovering a list entry reaches `PlaySoundFile`
  with the string channel.
- PALADIN regression: shipped `"Master"` leaf used, and a picked `"SFX"` is used.
- W2: a throwing `PlaySoundFile` and a throwing `StopSound` are both contained by the
  `pcall` (`preview_sound` does not error; a failed stop still lets the next preview play).
- W2/f: second preview stops the latched handle (exactly one stop, the right handle).
- W4: unknown key and a non-string map entry never reach `PlaySoundFile`; source pins hold
  the old plain reads out and keep both `pcall`s.

### 3c. Mutation proofs (red-first, on `/tmp` copies rebuilt from the final tree)

Run in one shot; `/tmp/opencode` is shared with other lanes and was wiped once mid-run, so
re-run the block if the copies are gone. Fixed copy: `PASS rotationtext_state.lua (286 checks)`.

| # | Mutation | Result |
|---|---|---|
| **M1** | restore the exact pre-fix `sound_channel()` (plain reads) | **10 of 286 FAIL**, incl. `W1: the channel handed to PlaySoundFile is a STRING, never the metatable's table (got table)`, `W1: an absent channel falls back to the shipped default (got table: 0x…, want Master)`, `W1: the class-row read created no key (got table…)`, `W4: … (2 rawgets)` |
| **M2** | drop both `pcall`s (`will_play, handle = play_sound_file(...)`, bare `stop_sound(...)`) | **3 of 286 FAIL** — both throwing-client checks plus the source pin |
| **M3** | `rawget` the profile root, keep the old plain class-row read | **3 of 286 FAIL** — the class-row key is created (`got table`), rawget count drops to 3 |

M1 is the money shot: the exact old code hands `PlaySoundFile` a **table**
(`PlaySoundFile: <table>` in the recording stub), which is the defect the brief describes.

---

## 4. Gate state

`bash tests/run.sh` on this tree, final run **2026-10-28 05:11**:
**54 steps, 0 failed**; `luacheck .` **2 warnings / 0 errors in 97 files** (the pre-existing
baseline — unchanged by this lane; `widgets.lua` and `tests/rotationtext_state.lua` are
clean on their own).

- **No red checks to attribute.** The mid-flight RED the brief warned about (stale
  placement pins in `tests/bars_state.lua`, owned by the `ranged-forced` lane) had already
  been re-cut before this lane started: the baseline gate at 05:00 was green too. Nothing
  here touched that lane's pins.
- Caveat on the number: `bars.lua` (mtime 05:01) and `tests/bars_state.lua` (05:05) were
  being edited concurrently while this lane ran, so the green is a **snapshot of the
  combined tree at 05:11**, not a verdict on that lane's final state.
- My suite alone: `PASS rotationtext_state.lua (286 checks)`.

---

## 5. W4 sweep of `widgets.lua`

The full sound path was walked for plain reads of possibly-missing keys:

| read | metatable-backed? | outcome |
|---|---|---|
| `ST.db.profile[ST.player_class]` | **yes** (`'**'` on the profile root) | fixed: `rawget`, token guarded |
| `class_db.sound_channel` | **yes** (`'**'` on the class row) | fixed: `rawget` + string requirement |
| `ST.db.profile.sound_channel` | **yes** (profile root) | fixed: `rawget` + string requirement |
| `st.widgets.twist_sounds`, `st.bar.twist_sounds`, `ST[ST.player_class]`, `class.on_*`, `map[key]`, `item.userdata.value` | no (plain addon/class tables) | left as-is |
| `play_sound_file`, `stop_sound` (captured with `rawget(_G, …)`) | already rawget | left as-is |

No other metatable-triggering read exists in the file. Two siblings outside my write
scope are listed in §6.

---

## 6. Outside scope — found by the sweep, NOT touched

1. **`classes/paladin.lua:1151-1157` `play_twist_sound`** — the *actual* twist playback
   path (not previews):
   `PlaySoundFile(path, db.sound_channel or "Master")`, unpcall'd, and `db` is the class
   profile row (`classes/paladin.lua:1939` → `self:get_class_table()` →
   `main.lua:240-244` `profile[self.player_class]`), i.e. the same `'**'`-backed table.
   PALADIN ships a string leaf so it is safe today; this is the identical latent class as
   the defect fixed here and it fires on a real play path. **Recommend a follow-up lane**
   owning `classes/paladin.lua` (rawget + string requirement + pcall).
2. **`main.lua:233-245` `ST:get_class_table()`** — `profile[self.player_class]` is a plain
   read on the `'**'`-backed profile root; it would materialise a row for a class token the
   defaults do not list. Harmless today (all ten tokens are defaults keys) but the same
   pattern. Not mine.
3. The F2 appearance migration (`config.lua`) is the sibling lane's fix — untouched here.

No disagreement to escalate: these are new latent findings outside the lane's write scope,
not a dispute with another desk. Recorded here for dispatch; no `hands-up.md` row filed.

---

## 7. Needs a live client (UNVERIFIED)

- That `PlaySoundFile` returns `(willPlay, handle)` on every target family and that
  `"Master"`/`"SFX"`/`"Music"`/`"Ambience"` are accepted channel names there. Offline
  proves only the **argument type and containment**, not the client's answer.
- That hovering an entry in the two PALADIN `Dropdown-SoundPreview` selects actually
  previews on a live client (needs the paladin panel open + the class sound map).
- That the real client's failure mode is contained: the offline stub **throws**; a client
  may instead return `false` — both paths are handled, but only the client can show which
  it does.
- Not needing a client: the `'**'` creation behaviour itself (driven over the shipped
  AceDB object offline).

---

## 8. Files changed

| File | Lines | Change |
|---|---|---|
| `widgets.lua` | 240 (+30) | rawget + string-required channel resolution, shipped default, `pcall` on both client sound calls, non-string map-entry guard |
| `tests/rotationtext_state.lua` | 1120 (+272) | section 7b: real-AceDB `'**'` fixture + W1/W2/W4 runtime proof + hover path + paladin regression + static pins; header bullet |

Version **2.1.3** unchanged; no TOC/Libs/docs/lint-config edits; no git.

# Forever range bar, power-bar text, HUD secret defence and single TOC — 2026-11-07

Operator report (in-client, WoW Forever 1.60.1): "range bar is showing without displaying how
far things are. its just grey"; "u didnt pass the power bar text correctly. but it is showing
and working"; "make sure you got all the secret data correct for hud"; "we also need to do a
toc update, and we need to get rid of all the extra toc files and just use 1 for all clients."

All work is offline-verified. The in-client pass is still the only close for the items marked
UNCONFIRMED at the end.

## 1. Why the range bar was grey

The bar's only distance source was `st.api.UnitDistance`, a wrapper over
`UnitDistanceSquared`. Evidence from the client's own API docs and the wiki:

- `origin/forever:Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua`
  `Name = "UnitDistanceSquared"` — `distance, checkedDistance`, no secret markers.
- The only Blizzard caller on `origin/forever` is
  `Blizzard_UnitFrame/Shared/CompactUnitFrame.lua:1069`, inside the party/raid
  `UNIT_DISTANCE_CHECK_UPDATE` handler.
- Warcraft Wiki `API:UnitDistanceSquared` (Forever 1.60.1 is listed as a game type):
  "Returns the squared distance to a unit in your group"; `checkedDistance` is false "if
  unit not found or not in your group"; the page is marked `#noinstance` (outdoors only).
  https://warcraft.wiki.gg/wiki/API:UnitDistanceSquared
- `UnitPosition` has the same group-only/`#noinstance` restriction (wiki page), so it cannot
  measure an enemy either. `CheckInteractDistance` is `#nocombat` since 10.2 and was already
  removed by HU-23 after the TBC `ADDON_ACTION_BLOCKED` log.

So an attackable enemy target normally reports unknown: the wrapper returns nil, and the bar
painted its explicit `--` unknown face. The defect is the single-source design, not the paint.

### Fix: second exact tier (native swing-range check)

`origin/forever:.../SwingTimerDocumentation.lua` documents
`C_SwingTimer.IsTargetWithinSwingRange(swingType)` (0 MainHand, 1 OffHand, 2 Ranged): "Whether
the current target is within range of the player's auto attack"; nil "when no range check could
be made" and must not be treated as out of range. `compat.lua` already wraps it
(`api.is_target_in_swing_range`, used by the ranged swing bar in `main.lua:264`).

`weave_range.lua` now has two exact tiers, never a guess:

1. `st.api.UnitDistance` -> exact yards (`12 yd  IN RANGE`).
2. `st.api.is_target_in_swing_range` -> exact band: `<=5 yd  MELEE`, `5-35 yd  IN RANGE`,
   `>35 yd  OUT`; outside melee with no ranged check -> `>5 yd  OUT`. The band fill is a
   marker (1 / 0.5 / 1 px), never a fabricated yard position.
3. Both silent -> the existing `--` unknown face (still visible).

The `/st diag` `weave=` token gained `src=<exact|swing|none>` so the operator can see which tier
answered. This supersedes HU-23's "exact yards only" wording for the enemy case; it does not
reintroduce `CheckInteractDistance`, LibRangeCheck or any protected call.

## 2. Power-bar text

`power_bar.lua` printed the constant `?` for a restricted reading. The Forever client's
`FontString:SetText` is `SecretArguments = "AllowedWhenTainted"` with
`SecretArgumentsAddAspect = { Enum.SecretAspect.Text }`
(`origin/forever:.../SimpleFontStringAPIDocumentation.lua`, `Name = "SetText"`), and Blizzard's
own unit frames pass a `SecretReturns = true` number straight in:
`CompactUnitFrame_UpdateStatusText` -> `statusText:SetText(UnitHealth(frame.displayedUnit))`
(`Blizzard_UnitFrame/Shared/CompactUnitFrame.lua:1101`; `UnitHealth` is `SecretReturns = true`
in `UnitDocumentation.lua:1526-1541`).

The restricted branch now calls `frame.text:SetText(state.value)` with the raw number (no
format, compare or latch — a secret cannot be compared), so the client renders the value. The
StatusBar fill pass-through is unchanged.

## 3. HUD secret data

Audit result: the HUD's restricted faces were already correct — `api.GetInventoryItemCooldown`
fourth return drives the trinket tri-state, class providers set `restricted=true` with no
timing numbers, `api.UnitAura` returns a secret entry as absent, and `CooldownFrame:SetCooldown`
is `IsProtectedFunction = true` + `AllowedWhenUntainted` on Forever (it cannot take secrets from
addon code), so a restricted cooldown must stay grey with no swipe/text.

Added defence in depth: `api.is_secret` (compat) is exposed, and `HUD.paint` re-checks
`remaining`/`duration`/`text_remaining`/`start` before comparing them. A provider that forgets
`restricted=true` and leaks a secret number now lands on the same grey unknown face instead of
raising and taking the HUD tick down. Exact no-op on classic clients (no `issecretvalue`).

## 4. Single TOC

The six flavor TOCs were deleted; `SwedgeTimer.toc` is the only one:

```
## Interface: 11509, 20506, 38002, 40402, 50500, 120100, 120105, 16001
```

`LibClassicSwingTimerAPI` must stay listed for Era/TBC/Wrath and must not run on
Forever/Retail/Cata/Mists. Without editing `Libs/`, the load is gated through LibStub's own
contract (`LibStub:NewLibrary` returns nil when an equal-or-higher minor is registered;
`Libs/LibStub/LibStub.lua:20-28`, and the library returns at `if not lib then return end`):

- `swing_lib_gate.lua` (listed before the library) registers a tagged stub at
  `GATE_MINOR = 1000000` on every non-classic-line client (Forever, Retail, Cata, Mists,
  unknown; interface fallback mirrors compat: 16000+ is Forever, majors 1/2/3 are classic-line).
- `swing_lib_gate_release.lua` (listed immediately after the library) removes the stub and its
  minor, so the shared LibStub registry is never poisoned for other addons.
- `main.lua` treats a tagged stub as absent (belt and braces).

`tests/toc_check.lua` now pins the single-TOC contract (one root TOC, the interface list, gate
before library before release, gate minor > vendored minor, the tag in main.lua) and
`tests/swing_gate_state.lua` pins the gate both ways (classic clients untouched; gated clients
blocked; release restores the registry; interface fallback).

## 5. Verification

- `bash tests/run.sh`: **58 steps / 0 failed**.
- `luacheck .`: **2 warnings / 0 errors in 103 files** (the two pre-existing `hunter_ui.lua`
  cast-zone constants).
- Version 2.1.8 in `SwedgeTimer.toc` and `main.lua:5` (no bump ordered).
- Mutation proofs (isolated workspace copy, each mutant exits non-zero):
  | Mutant | Killed by |
  | --- | --- |
  | power text `SetText(state.value)` -> `SetText("?")` | `power_bar_state` SEC-11 |
  | weave `swing_band` melee read disabled | `weave_bar_state` band |
  | HUD `api.is_secret` guard disabled | `hud_state` SEC-12 |
  | `GATE_MINOR = 1000000` -> `1` | `swing_gate_state` |
  | TOC gate line removed | `toc_check` |

## 6. UNCONFIRMED (in-client only)

- Whether the live Forever client answers `IsTargetWithinSwingRange` for an enemy target in
  the open world and in an instance (the band labels depend on it). `/st diag` `src=` says.
- Whether `UnitDistanceSquared` ever answers for an enemy outdoors on Forever (the wiki says
  group-only; if it does, tier 1 shows yards and tier 2 covers instances).
- That `FontString:SetText(secret number)` renders on 1.60.1 exactly as the doc/Blizzard call
  site imply.
- That the client accepts the 8-value `## Interface` list and loads the single TOC on every
  family (CurseForge upload is the operator's check).

## 7. Follow-ups

- In-client `/st diag` line to confirm the range `src=` tier and the power text.
- HUD `?` marker on the grey face is still the open L5 item (the restricted cooldown face is
  intentionally blank).
- No git commit; operator owns git/publish.

# Secret-API matrix — SwedgeTimer vs wow-ui-source origin/forever — 2026-11-09

Desk: secret-api-matrix (audit). Target tree: /home/sam/SwedgeTimer working tree, 2026-11-09.
Client reference: origin/forever @ eac30af597e5aaa43a60f6675ef5fdcea100375f (WoW Forever /
Camelot, Interface 16001, WOW_PROJECT_CAMELOT = 18, Mainline-code — st.is_mainline == true).
Cited as origin/forever:path:line for client facts, file:line for addon facts.

Supersedes bench/secret_api_matrix_2026-11-06.md. That file was a read-only desk report and is
preserved byte-for-byte at bench/secret_api_matrix_2026-11-06.prior-readonly.md; nothing in it was
overwritten. This run re-derives the predicate set against today's tree and adds the two things it
lacked: a per-consumer classification of every call site in classes/, hud.lua, forever_guide.lua,
hunter_ui.lua, and a direct-call (non-compat) audit.

---

## 0. Classification used in this matrix

**(a) legal pass-through sink** — a secret value reaches a widget method that is documented
SecretArguments = "AllowedWhenTainted" with the matching SecretArgumentsAddAspect, and is never
compared, indexed, concatenated or formatted on the way. The four sink families:

| Sink | Documentation (origin/forever) | Aspect |
|------|-------------------------------|--------|
| StatusBar:SetValue / SetMinMaxValues | SimpleStatusBarAPIDocumentation.lua:229-236, :355-361 | BarValue |
| FontString:SetText / SetFormattedText | SimpleFontStringAPIDocumentation.lua:664-670 | Text |
| Region:SetAlphaFromBoolean | SimpleRegionAPIDocumentation.lua:134-137 | Alpha |
| Region/Texture:SetVertexColor, StatusBar:SetStatusBarColor | SimpleRegionAPIDocumentation.lua:191-194, SimpleStatusBarAPIDocumentation.lua:282-292 | VertexColor, Alpha |

**(b) degrade-to-unknown** — the consumer refuses the secret (compat hands it nil, or an opaque
value plus a restricted flag) and marks the tick unknown instead of claiming a fact. Marker forms:
inputs_unknown (guide provider -> forever_guide), s.restricted (HUD provider -> hud.lua paint),
s.hidden / widget hidden (display-only).

The **Unknown marker** column records which of those fired. "none — reads as ready" marks a (b)
whose *flag* is dropped: the value is withheld but a restricted read renders exactly like an idle
one. Those are the defects listed in §5; they are still (b) by the definition above (no secret is
ever compared), but the user is told nothing.

---

## 1. Predicate inventory — the SecretWhen set that attaches to APIs this addon calls

origin/forever attaches 222 SecretWhen predicates across 9,772 documented names in
Interface/AddOns/Blizzard_APIDocumentationGenerated. The addon calls 18 of those APIs, carrying 12
distinct SecretWhen predicates plus one SecretReturns:

| # | Predicate | API(s) the addon calls | Citation (origin/forever) | Evaluated by |
|---|-----------|------------------------|---------------------------|--------------|
| 1 | SecretWhenUnitPowerRestricted | UnitPower | UnitDocumentation.lua:2732-2734 | compat.lua:862-868 (nil) / :903-913 (raw+flag) |
| 2 | SecretWhenUnitPowerMaxRestricted | UnitPowerMax | UnitDocumentation.lua:2801-2803 | compat.lua:875-881 |
| 3 | SecretReturns (not SecretWhen) | UnitHealth | UnitDocumentation.lua:1526-1529 | compat.lua:950-956 |
| 4 | SecretWhenUnitHealthMaxRestricted | UnitHealthMax | UnitDocumentation.lua:1472-1474 | compat.lua:963-969 |
| 5 | SecretWhenAurasRestricted | UnitAura (legacy global) | UnitAuraDocumentation.lua:645-648 | compat.lua:1014-1053 (whole entry -> nil) |
| 6 | SecretWhenCooldownsRestricted | GetSpellCooldown | SpellDocumentation.lua:309-313 | compat.lua:500-532 (5th return) |
| 7 | SecretWhenUnitIdentityRestricted | UnitGUID, UnitCreatureType | UnitDocumentation.lua:1241-1243, :1030-1032 | compat.lua:2145-2154, :2196-2205 |
| 8 | SecretWhenUnitComparisonRestricted | UnitIsUnit | UnitDocumentation.lua:2410-2413 | compat.lua:2169-2189 (opaque + flag) |
| 9 | SecretWhenUnitSpellCastRestricted | UnitCastingInfo, UnitChannelInfo | UnitDocumentation.lua:828-830, :870-872 | compat.lua:1295-1318 |
| 10 | SecretWhenTotemSlotSecret | GetTotemInfo | TotemDocumentation.lua:59-62 | compat.lua:1992-2010 |
| 11 | SecretWhenUnitStatsRestricted | UnitSpellHaste, GetUnitSpeed, GetCombatRating, GetCombatRatingBonus, UnitAttackSpeed, UnitRangedDamage | UnitDocumentation.lua:3132-3134, :335-337; PlayerScriptDocumentation.lua:303-305 | compat.lua:1365-1384, :1715-1728, :1758-1778, :1464-1490 |

**Called but NOT restricted on this branch** (checked, so no finding is invented for them):

| API | What the docs actually say |
|-----|----------------------------|
| UnitPowerType | no predicate, no SecretReturns — UnitDocumentation.lua:2859-2862 (SecretArguments = "AllowedWhenUntainted" only). compat still nils a secret answer defensively (compat.lua:925-933). |
| C_Item.GetItemCooldown | MayReturnNothing + SecretArguments = "AllowedWhenUntainted", no SecretWhen — ContainerDocumentation.lua:337-340. |
| GetSpellHaste | **not documented at all** on origin/forever (no Name = "GetSpellHaste" entry in the generated docs). compat guards it defensively (compat.lua:1376-1382); the client fact is UNVERIFIED. |
| GetInventoryItemCooldown | **not documented at all** on origin/forever. compat synthesises the 4th "restricted" return (compat.lua:1836-1855); hud.lua relies on that flag. UNVERIFIED as a client fact. |

---

## 2. Consumer matrix

Every call site of a predicate-carrying API inside the four audited scopes. "Flag" = the
compat-side restricted signal (5th/4th return or is_secret probe) that the site consumes.

### 2.1 hud.lua

| # | Site | API (predicate) | Consumer behaviour | Class | Unknown marker |
|---|------|-----------------|--------------------|-------|----------------|
| H1 | hud.lua:343 | UnitAura (5) | trinket proc scan: a secret row reads absent, scan continues to the 40-row cap; re-proved with is_secret before the cache write (:345, :353) | (b) | none — proc stamp simply absent |
| H2 | hud.lua:376 | GetInventoryItemCooldown (no predicate on branch) | 4th return -> trinket_has_on_use returns nil = "unknown, keep the slot" | (b) | s.restricted (hud.lua:499) + one-time notice :500 |
| H3 | hud.lua:480-487 | GetInventoryItemCooldown | same read inside trinket_state; a poisoned value forces (nil, nil, nil, true) | (b) | s.restricted |
| H4 | hud.lua:1549-1558 | any (poisoned state) | paint re-derives restricted from is_secret on every timing field and refuses every comparison | (b) | restricted face (grey, no swipe) |
| H5 | hud.lua:1917-1938 | any (poisoned state) | state normaliser: poisoned timing fields dropped, out.restricted = true | (b) | out.restricted |

Note: hud.lua has **no** StatusBar/SetText sink for a secret in this scope — the HUD is icon-based
(SetVertexColor/SetText with computed numbers only, hud.lua:1756, :1810). Its restricted handling is
therefore all (b).

### 2.2 forever_guide.lua

| # | Site | API (predicate) | Consumer behaviour | Class | Unknown marker |
|---|------|-----------------|--------------------|-------|----------------|
| G1 | forever_guide.lua:479-501 | GetSpellCooldown (6) | reads the 5th return, re-reads via the fallback id, sets restricted_state; rem/dur stay 0 so no swipe is invented | (b) | s.restricted (forever_guide.lua:611) |
| G2 | forever_guide.lua:524-531 | GetSpellCooldown (6) | GCD echo probe; a restricted read yields 0/0 and the echo is simply skipped (no fabricated GCD swipe) | (b) | covered by G1's restricted_state |
| G3 | forever_guide.lua:566-569 | UnitCreatureType (7) | nil ctype -> no Undead/Demon Exorcism glow; nil is never read as "not undead" | (b) | none — cue not emitted |
| G4 | forever_guide.lua:1522-1547 | UnitAura (5) via scan_unit_aura + C_Secrets probes | nil mark + may-be-secret -> "unknown" -> treated as active for the rule AND restricted_seen | (b) | inputs_unknown (:1649 -> :1725-1727) |
| G5 | forever_guide.lua:1705, :1725-1727 | all (6) | propagates raw_inputs.inputs_unknown and any restricted_seen to the output | (b) | inputs_unknown |

### 2.3 hunter_ui.lua

| # | Site | API (predicate) | Consumer behaviour | Class | Unknown marker |
|---|------|-----------------|--------------------|-------|----------------|
| U1 | hunter_ui.lua:1146-1158 | UnitIsUnit (8), source classes/hunter.lua:1640 | restricted -> frame shown, opaque boolean handed to SetAlphaFromBoolean(label, warn, 1, 0); no text/colour branch runs; client without the sink hides + says so once | **(a)** | alpha itself (sanctioned sink) |
| U2 | hunter_ui.lua:1361-1367 | UnitAura (5) | Rapid Fire scan walks past secret rows to the cap instead of breaking; no match = bar hidden | (b) | none — bar hidden |
| U3 | hunter_ui.lua:1491-1500 | UnitAura (5) | pet Frenzy scan, same walk-past rule | (b) | none — badge hidden |
| U4 | hunter_ui.lua:1842-1855 | UnitAura (5) | aspect scan, same walk-past rule | (b) | none — aspect icon hidden |
| U5 | hunter_ui.lua:1405-1407 | (sink) StatusBar SetValue + SetText | fed only by duration/expiration of a row that passed the scan; a secret row never reaches it | (a) sink, no secret input | n/a |

U1 is the only true pass-through in the audited scope: UnitIsUnit is SecretWhenUnitComparisonRestricted
(UnitDocumentation.lua:2413) and the documented addon-side sink for it is SetAlphaFromBoolean
(SimpleRegionAPIDocumentation.lua:134-137). Blizzard does the same at
Blizzard_UnitFrame/Shared/UnitFrameUtil.lua:487 on the same branch.

### 2.4 classes/druid.lua

| # | Site | API (predicate) | Consumer behaviour | Class | Unknown marker |
|---|------|-----------------|--------------------|-------|----------------|
| D1 | classes/druid.lua:507-512 | UnitPower (1) | nil cost reading -> "cannot claim short of rage", state untouched | (b) | none |
| D2 | :545-549 | UnitPower (1) | nil -> return; never closes a segment or counts an event | (b) | none |
| D3 | :1293 | UnitAura (5) | target HARMFUL walk, no early break | (b) | none |
| D4 | :1399 | UnitAura (5) | player HELPFUL walk, no early break | (b) | none |
| D5 | :1514-1516 | UnitPower (1) | nil -> energy anchor not updated | (b) | none |
| D6 | :1643-1646 | UnitPower (1) | nil -> energy text hidden | (b) | widget hidden |
| D7 | :1680-1685 | UnitPower (1) | nil -> combo pips hidden | (b) | widget hidden |
| D8 | :2128 | UnitPowerType (no predicate) | nil -> no energy tick bar | (b) | none |
| D9 | :2439-2444 | UnitGUID (7) | nil -> TTD baseline dropped; never compares an opaque identity | (b) | none |
| D10 | :2457 | UnitHealth (3) | nil -> no TTD estimate, baseline dropped | (b) | none |
| D11 | :2291-2303 | GetSpellCooldown (6) | guide_cooldown_remaining reads the 3-value restricted helper; restricted -> nil + guide_reads_unknown | (b) | inputs_unknown (:3062-3063) |
| D12 | :2566-2604 | UnitPower/UnitPowerMax (1,2) | unreadable pool + power_may_be_secret -> note_secret_pool, field never published as 0 | (b) | inputs_unknown (:3062-3063) |
| D13 | :3024-3027 | UnitHealth/UnitHealthMax (3,4) | both numeric required; otherwise player_health_pct simply not set | (b) | none |
| D14 | :3040 | UnitAura (5) | Lacerate upkeep walk, no early break | (b) | none |
| D15 | :3370-3379 | GetSpellCooldown (6) | hud_ability_cooldown takes only the classic 4 values; a restricted read is (0,0) and is returned as "0 = ready, full duration" | (b), flag dropped | **none — reads as ready** |
| D16 | :3504-3507 | UnitHealth/UnitHealthMax (3,4) | numeric-only, else no pct | (b) | none |

### 2.5 classes/hunter.lua

| # | Site | API (predicate) | Consumer behaviour | Class | Unknown marker |
|---|------|-----------------|--------------------|-------|----------------|
| Hu1 | classes/hunter.lua:1059-1061 | GetSpellCooldown (6) | Auto Shot window sync: restricted -> (0,0,0) -> treated as "no Auto Shot", sync skipped | (b), flag dropped | **none — reads as inactive** |
| Hu2 | :1282 | UnitChannelInfo (9) | nil payload -> "no cast running" | (b) | none |
| Hu3 | :1380-1383 | UnitGUID (7) | nil target guid -> comparison short-circuited, no opaque compare | (b) | none |
| Hu4 | :1591, :1598 | UnitGUID (7) | stored as the tint baseline; nil never equals anything | (b) | none |
| Hu5 | :1640-1647 | UnitIsUnit (8) | hands (opaque boolean, true) up unchanged | **(a)** source for hunter_ui U1 | n/a |
| Hu6 | :1897-1900 | UnitPower/UnitPowerMax (1,2) | numeric-only, else nil | (b) | none |
| Hu7 | :2588-2595 | GetUnitSpeed (11) | nil -> motion unknown, never "standing still" | (b) | none |
| Hu8 | :2736-2750 | GetSpellCooldown (6) | guide helper, restricted-aware; restricted -> nil + guide_reads_unknown | (b) | inputs_unknown (:3727-3728) |
| Hu9 | :3549-3560 | UnitHealth/UnitHealthMax (3,4) | restricted pair -> target_hp_frac withheld, tick flagged | (b) | inputs_unknown |
| Hu10 | :3651-3656 | UnitPowerType + power_may_be_secret | may-be-secret power type -> guide_reads_unknown | (b) | inputs_unknown |
| Hu11 | :3931-3940 | GetSpellCooldown (6) | hud_ability_cooldown, classic 4 values only | (b), flag dropped | **none — reads as ready** |

### 2.6 classes/paladin.lua

| # | Site | API (predicate) | Consumer behaviour | Class | Unknown marker |
|---|------|-----------------|--------------------|-------|----------------|
| P1 | classes/paladin.lua:606-620 | UnitAura (5) | seal scan, nil row = no match, walk continues | (b) | none |
| P2 | :996 | **bare UnitGUID** (7) | direct global, unguarded — see DC3 | — | direct-call defect |
| P3 | :1321-1329 | GetSpellCooldown (6) | Judgement swing marker: 4 values only; restricted -> duration 0 -> marker hidden | (b), flag dropped | none — marker absent |
| P4 | :2433-2440 | UnitAura (5) | JotC target walk | (b) | none |
| P5 | :2498-2512 | GetSpellCooldown (6) | get_guide_cooldown_remaining, restricted-aware; restricted -> nil + guide_reads_unknown | (b) | inputs_unknown (:3891-3892) |
| P6 | :2544-2564 | UnitPower/UnitPowerMax (1,2) | power pct returns (nil, true) on a may-be-secret power type | (b) | guide_reads_unknown (:2510) |
| P7 | :2571-2579 | **bare UnitCreatureType** (7) | direct global, but is_secret-guarded -> nil | (b) | none — see DC4 |
| P8 | :2883-2890 | UnitAura (5) | JotC upkeep walk | (b) | none |
| P9 | :3087-3092 | GetSpellCooldown (6) | CD-icon row, 4 values only -> a restricted read shows no swipe | (b), flag dropped | **none — reads as ready** |
| P10 | :3323-3326 | UnitHealth/UnitHealthMax (3,4) | pct only when both readable | (b) | none |
| P11 | :4263-4467 (hud_ability_cooldown family: :4313, :4336, :4361, :4382, :4402, :4428, :4441, :4454, :4467) | GetSpellCooldown (6) | cs/judgement go through the restricted-aware helper; the remaining slots take the classic 4 values | mixed: (b) with inputs_unknown for cs/judgement, (b) flag-dropped for the rest | **none for the rest** |

### 2.7 classes/rogue.lua

| # | Site | API (predicate) | Consumer behaviour | Class | Unknown marker |
|---|------|-----------------|--------------------|-------|----------------|
| R1 | classes/rogue.lua:347 | UnitAura (5) | shared aura match helper, nil row = no match | (b) | none |
| R2 | :392-403 | GetSpellCooldown (6) | spell_cooldown, restricted-aware | (b) | inputs_unknown (:1349-1350) |
| R3 | :513-518, :541-546 | C_Item.GetItemCooldown (no predicate) | compat answers (0,0,0) for a secret read with **no flag to read** -> "item ready" | (b), flag unavailable | **none — reads as ready** |
| R4 | :763-768, :985-990 | UnitPower/UnitPowerMax (1,2) | numeric-only, else nil | (b) | inputs_unknown (:1345) |
| R5 | :803-807 | UnitGUID (7) | nil -> TTD baseline dropped | (b) | none |
| R6 | :819 | UnitHealth (3) | nil -> no TTD estimate | (b) | none |
| R7 | :1308-1311 | is_secret probe on a base cooldown | secret -> field withheld | (b) | none |
| R8 | :1409, :1523, :1631 | C_Secrets.ShouldAurasBeSecret via api.auras_may_be_secret | auras may be secret -> s.hidden = true for the lust slot | (b) | s.hidden |
| R9 | :1344-1353 | UnitPower (1) | non-numeric energy/cp or lust unknown -> inputs_unknown | (b) | inputs_unknown |

### 2.8 classes/shaman.lua

| # | Site | API (predicate) | Consumer behaviour | Class | Unknown marker |
|---|------|-----------------|--------------------|-------|----------------|
| S1 | classes/shaman.lua:762-768 | UnitSpellHaste (11) | nil -> tries GetSpellHaste, then 0 | (b) | none — 0 is a real fallback value |
| S2 | :798 | UnitAura (5) | Maelstrom Weapon walk | (b) | none |
| S3 | :972-976 | UnitCastingInfo/UnitChannelInfo (9) | nil payload -> "no cast" | (b) | none |
| S4 | :1097-1101 | GetTotemInfo (10) | nil -> twist totem leg returns (inert) | (b) | none |
| S5 | :1242-1244 | GetTotemInfo (10) | nil -> (nil, nil); caller hides | (b) | widget hidden |
| S6 | :1861 | UnitAura (5) | Flame Shock upkeep walk | (b) | inputs_unknown via flameshock_allowed = nil |
| S7 | :2110, :2158, :2187 | GetSpellCooldown (6) | SS/SR badges take the classic 4 values; restricted -> no badge | (b), flag dropped | **none — reads as ready** |
| S8 | :2898-2912 | GetSpellCooldown (6) | guide cooldown, restricted-aware | (b) | inputs_unknown (:3769-3770) |
| S9 | :3326-3331 | UnitPower/UnitPowerMax (1,2) | numeric-only, else no fraction | (b) | none |
| S10 | :3460-3462 | GetTotemInfo (10) | **nil (unreadable/restricted) -> inputs.fireele_active = true** — a claim derived from an unknown, justified in the comment as "trust the commit stamp" | (b) but **claims ACTIVE** | none — asserted active |
| S11 | :3692-3693 | api.auras_may_be_secret | auras may be secret -> watershield cue suppressed | (b) | none |
| S12 | :3718-3721, :4099-4101 | GetTotemInfo (10) | nil -> hidden / no WF claim | (b) | widget hidden |
| S13 | :4000-4003 | GetSpellCooldown (6) | hud_ability_cooldown, classic 4 values | (b), flag dropped | **none — reads as ready** |

### 2.9 classes/warrior.lua

| # | Site | API (predicate) | Consumer behaviour | Class | Unknown marker |
|---|------|-----------------|--------------------|-------|----------------|
| W1 | classes/warrior.lua:1174-1177 | is_secret probe on a spell cost | secret -> nil cost | (b) | none |
| W2 | :1185-1190 | UnitPower (1) | nil -> cannot claim short of rage | (b) | none |
| W3 | :1469 | UnitAura (5) | Bloodsurge walk | (b) | none |
| W4 | :2190-2195 | UnitHealth/UnitHealthMax (3,4) | numeric-only, else nil | (b) | none |
| W5 | :2270 | UnitPower (1) | nil rage passed to record_execute_sample, which nils non-numbers (:2204-2213) | (b) | none |
| W6 | :2371, :2428 | UnitAura (5) | target/player walks, no early break (:2371 comment pins it) | (b) | none |
| W7 | :2514-2518 | UnitCastingInfo/UnitChannelInfo (9) | nil payload -> "no cast" | (b) | none |
| W8 | :3417-3424 | UnitHealth/Max + UnitPower (1,3,4) | nil pct or nil rage -> get_bank_state returns false (type checks at :2089-2094) | (b) | none — widget not shown |
| W9 | :3652-3665 | GetSpellCooldown (6) | guide cooldown, restricted-aware | (b) | inputs_unknown (:4634-4635) |
| W10 | :4089-4096 | UnitPower (1) | non-numeric rage -> guide_reads_unknown | (b) | inputs_unknown |
| W11 | :4110-4113 | UnitHealth/Max (3,4) | numeric-only, else no pct | (b) | none |
| W12 | :4626-4628 | UnitHealth/Max (3,4) | numeric-only, else no pct | (b) | none |
| W13 | :5146-5149 | GetSpellCooldown (6) | hud_ability_cooldown, classic 4 values | (b), flag dropped | **none — reads as ready** |
| W14 | :5198-5201 | UnitHealthMax/UnitHealth (3,4) | numeric-only, else false | (b) | none |

---

## 3. Counts

| File | Sites | (a) pass-through | (b) degrade, marked | (b) degrade, flag dropped |
|------|-------|------------------|---------------------|---------------------------|
| hud.lua | 5 | 0 | 5 | 0 |
| forever_guide.lua | 5 | 0 | 5 | 0 |
| hunter_ui.lua | 5 | 2 (U1 sink, U5 sink) | 3 | 0 |
| classes/druid.lua | 16 | 0 | 14 | 1 (D15) + 1 mixed |
| classes/hunter.lua | 11 | 1 (Hu5 source) | 9 | 2 (Hu1, Hu11) |
| classes/paladin.lua | 11 | 0 | 9 | 3 (P3, P9, P11 rest) |
| classes/rogue.lua | 9 | 0 | 7 | 2 (R3 flag unavailable) |
| classes/shaman.lua | 13 | 0 | 11 | 2 (S7, S13) |
| classes/warrior.lua | 14 | 0 | 13 | 1 (W13) |

Every site that receives a secret above is (b) except two: the UnitIsUnit -> SetAlphaFromBoolean
chain (classes/hunter.lua:1640 -> hunter_ui.lua:1146-1158) and the StatusBar/SetText sinks in
hunter_ui.lua whose inputs are pre-filtered to readable numbers.

---

## 4. Direct-call audit (calls that bypass st.api in the four scopes)

Scope: bare-global calls and rawget(_G, ...) aliases to a predicate-carrying name inside classes/,
hud.lua, forever_guide.lua, hunter_ui.lua. Scan covered both bare calls and the aliased forms
(local X = rawget(_G, "X")). libs/tests/docs excluded.

| # | Site | Code | Rule violated | Risk | Verdict |
|---|------|------|---------------|------|---------|
| DC1 | hud.lua:139 + :430-431 | local unit_guid = rawget(_G, "UnitGUID"); ... local me = self.player_guid or (unit_guid and unit_guid("player")); if me == nil or dest_guid ~= me then | UnitGUID is SecretWhenUnitIdentityRestricted (UnitDocumentation.lua:1241-1243); the call skips compat.lua:2145-2154 | a secret result reaches the ~= comparison at :431 and raises. Self-GUID is readable in practice, so the exposure is theoretical — but this is the one unguarded read left in the trinket event path (the dest_guid/spell_id arguments are already is_secret-guarded at :426) | **FIX** — use api.UnitGUID; nil already lands on the `me == nil` early return, so the patch is a one-word change with no behaviour change on any readable client |
| DC2 | forever_guide.lua:573-577 and :583-589 | local hp_fn = api.UnitHealth or UnitHealth ... (hp / max_hp) < 0.2 | UnitHealth carries SecretReturns (UnitDocumentation.lua:1528), UnitHealthMax SecretWhenUnitHealthMaxRestricted (:1474) | the fallback is dead today (compat always assigns both), but if it ever fired the arithmetic at :577/:587 would raise on a secret number | **FIX (cheap)** — delete the `or UnitHealth` / `or UnitHealthMax` fallbacks; they buy nothing and exist only as a landmine |
| DC3 | classes/paladin.lua:996 | if source_guid ~= UnitGUID("player") then | same identity predicate; skips compat | the CLEU handler runs only for paladins on non-mainline (main.lua:765 gate), so on Forever the path is unreachable; on Era/TBC there is no secret regime | **FIX (rule hygiene)** — api.UnitGUID returns nil on a secret, and `nil ~= source_guid` is already the correct "not ours" outcome |
| DC4 | classes/paladin.lua:2571-2579 | local ctype = UnitCreatureType("target"); if is_secret(ctype) then return nil end | identity predicate; skips compat | behaviour is correct (guarded, nil = unknown) but it is a second implementation of compat.lua:2196-2205 and drifts if compat changes | **FIX (dedupe)** — call api.UnitCreatureType |
| DC5 | classes/druid.lua:324, classes/paladin.lua:17, classes/rogue.lua:467, classes/warrior.lua:22 | local is_secret = issecretvalue or function() ... | meta-predicate read from the global rather than api.is_secret | none: this is the sanctioned question, not a secret read, and compat.lua:183-185 is a thin wrapper over the same global | **ACCEPT** — no secret value is touched |

Not audited (out of the four scopes, listed so the next reader is not surprised): main.lua:1020-1024,
:2322-2324, :2474 (UnitAttackSpeed / UnitRangedDamage), enemy_swing.lua:290-293,
practice_ui.lua:376, swing_source.lua:256-400, LibGlobalCooldown.lua:21-22 (GetCombatRating via api).

---

## 5. Findings, ranked

| # | Sev | Finding | Evidence | Fix |
|---|-----|---------|----------|-----|
| 1 | HIGH | **Flag dropped on every ability cooldown read except the guide helper.** Six per-class hud_ability_cooldown / marker / badge paths read only the classic 4 values of api.GetSpellCooldown. On Forever a restricted read is (0,0,0,0,true); those paths take duration 0 and render the slot as READY with a full-duration swipe and no restricted face. The guide text is suppressed correctly (inputs_unknown) but the icons contradict it. | D15, Hu1, Hu11, P3, P9, P11, S7, S13, W13 | switch every one to api.get_cooldown_remaining and set s.restricted (or hide) on true |
| 2 | MED | **Shaman Fire Elemental is asserted active from an unreadable slot.** `if have == nil then inputs.fireele_active = true` turns a restricted/unreadable GetTotemInfo into a POSITIVE fact; the guide then suppresses Fire Nova on a guess. | S10, classes/shaman.lua:3461-3462 | publish nil (unknown) and let the alias treat it as unknown |
| 3 | MED | **Rogue item cooldowns have no restricted channel at all.** compat.lua:2102-2111 returns (0,0,0) for a secret read with no 4th return, so the Thistle Tea / bandage legs cannot tell "ready" from "unknown" even if they wanted to. | R3, classes/rogue.lua:513-546 | add a 4th "restricted" return to api.GetItemCooldown like GetInventoryItemCooldown has |
| 4 | MED | **The HUD restricted face is unreachable from the cooldown path.** hud.lua paints s.restricted only when a poisoned value arrives (:1549-1558, :1917-1938) or on the trinket path (:499). A class provider that degrades a restricted cooldown to remaining = nil, restricted = nil paints an ordinary idle slot. | H4, H5, P5, D11 | have the class hud_ability_cooldown set s.restricted on the helper's true |
| 5 | LOW | **Direct-call violations** DC1-DC4 above: one unguarded identity compare (hud.lua:430-431), two dead raw-global fallbacks (forever_guide.lua:573-574, :583-584), one duplicated identity read (classes/paladin.lua:2571-2579). | §4 | as listed |
| 6 | LOW | **Two wrappers have no client-side definition to audit.** GetSpellHaste and GetInventoryItemCooldown are not documented on origin/forever, so no SecretWhen can be cited for them; compat guesses (nil on secret / synthesised restricted flag). hud.lua's trinket tri-state depends on that guess. | §1 | in-client probe: /run print(type(GetInventoryItemCooldown), GetInventoryItemCooldown("player", 13)) |

No secret value is compared, concatenated, used as a table key, or formatted in the audited scope.
Every nil-on-secret degrade found in §2 is consumed by a type() / == nil guard before any
arithmetic, which is the property the whole matrix was checked for.

---

## 6. UNVERIFIED (client-side facts this audit cannot close offline)

| # | Question | Why it stays open | How to close |
|---|----------|-------------------|--------------|
| V1 | Which of these predicates actually fire in ordinary Forever play? | requires a running client; the docs give the predicate, not the current regime | /run print(C_Secrets.ShouldUnitPowerBeSecret("player", 0), C_Secrets.ShouldAurasBeSecret(), C_Secrets.ShouldUnitHealthMaxBeSecret("target")) |
| V2 | Is GetSpellCooldown actually restricted (no readable fallback) on this client? | the 5th return only becomes true when the read is opaque AND the fallback id is also opaque | /run print(GetSpellCooldown(20271)) and inspect for secret values in-game |
| V3 | Does the client define GetInventoryItemCooldown / GetSpellHaste at all? | neither is in the generated API docs on origin/forever | /run print(type(GetInventoryItemCooldown), type(GetSpellHaste)) |
| V4 | Is UnitIsUnit("targettarget","player") genuinely opaque? | SecretWhenUnitComparisonRestricted is context-gated ("a compound token is always secret on an addon-restricted map") | watch hunter_ui.lua:1150 restricted == true in game (add a /st diag line if needed) |
| V5 | Does SetAlphaFromBoolean accept the opaque boolean on this client? | documented AllowedWhenTainted, but the in-client acceptance is not provable offline | enable hunter_target_warning on Forever and confirm the label fades without a Lua error |

---

## 7. Provenance

- Client facts: git -C /home/sam/wow-ui-source show origin/forever:Interface/AddOns/Blizzard_APIDocumentationGenerated/<file>.lua
  (branch sha eac30af597e5aaa43a60f6675ef5fdcea100375f).
- Predicate enumeration: every Name = "X" block in the 642 generated documentation files, filtered to
  the names the addon actually calls (compat.lua api surface + bare-global scan of the four scopes).
- Addon facts: the working tree at 2026-11-09, line numbers as cited.
- Prior art not re-derived: bench/powerbar_secret_2026-11-06.md (power pass-through),
  bench/secret_consumers_audit_2026-11-06.md (H1-H6 findings), bench/secret_api_matrix_2026-11-06.prior-readonly.md.

# lessons

earned once, written here, never argued away. newest last.

- **briefs live in files, not prompts.** long prompts can abort mid-flight
  ("This text request is too large"), and a lane in `error, unreconciled`
  state cannot be revived. write the brief to `bench/briefs/`, verify
  it exists, point the lane at it. (2026-10-17)
- **never gate on `st.is_mainline` alone.** the WoW Forever client is
  mainline-code but must behave like classic-line where swing features are
  concerned — gate on swing activity instead. (2026-10-17, cross-engine)
- **desk work needs write-capable desks.** hunter/proctor-type specialist
  lanes shipped read-only toolsets (no file-write/skill tools), so they
  cannot open desks, journal, emit signals, or leave bench files — the
  orchestrator filed their reports by hand. dispatch desk-owning work
  only to lanes with verified write access (general proved it 4/4).
  (2026-10-19)
- **verify line endings per file before asserting them in a brief.**
  compat.lua is LF, not CRLF — the brief claimed CRLF and the lane had
  to correct it. `file` check per target, every time. (2026-10-19)
- **firecrawl_search is broken on this deployment** (invalid request body;
  developer_search 404s). Research lanes enumerate both catalogs then let
  SearxNG carry the round — record which catalog actually served.
  (2026-10-19, two rounds hit it)
- **SoD and Era are the same client but different games — gate SoD behavior
  on rune/item knowledge, never on client version.** Operator-confirmed
  2026-10-19 (matches the sod-detect per-class ERA+known-spell mechanism).
  Applies to every future SoD branch.
- **TBC Anniversary API takes spell NAMES, not ids; Classic Era needs ids.**
  Operator-confirmed 2026-10-19. TBC paths resolve via client name (never
  bare id), Era paths via id — pin both resolutions.
- **a remembered id is a rumor.** confirmed = the source said it and the
  citation is on the bench (`bench/verify_bank.md` is the working
  example); otherwise UNCONFIRMED, in caps. (2026-10-17)
- **enumerate the tool catalog before scraping.** firecrawl exposes 28
  tools; agents used two because the brief said two. enumerate, then pick
  per job. (2026-10-17)
- **no default-visible change without an explicit gate.** new toggles ship
  nil-safe: `== false` hides, nil = off, defaults documented for the
  options pass. (standing)
- **the operator owns git.** desks never run version-control commands;
  all changes stay in place and stated. (standing)
- **every lane lists every file it changed.** mid-wave, SwedgeTimer.toc's Interface line changed (120100→120105) with no scoped owner — three lanes observed it, none owned it. observers did self-report; the changer didn't. reconcile restores test+matrix state and logs the ambiguity for the owner. (2026-10-17)
- **a display-only HUD mirror with NO default still runs its provider every
  tick.** `hud.lua`'s `icon_should_show` hides only on `== false`, so a nil
  `hud_show_<key>` counts as WANTED — the provider-level hide (the druid-Claw
  gate) is what keeps the slot invisible, and the row's width closes on the
  first tick's hidden-flip reflow. Every provider-call census therefore grows
  by one per mirror that has no default key in `config_presets.lua`. Decide
  explicitly whether the default lands in the same lane (the druid's Claw:
  `false` default + provider gate) or in the options pass. (2026-10-20,
  paladin HUD band)
- **a bench citation's line number is a claim, not a fact — re-read the source
  before inheriting it.** `bench/paladin_apl_utility_build_2026-10-20.md` cites
  `hammer_of_wrath.go:18` for `ExtraCastCondition`; the file has it at `:31-32`
  (`:18` is the ManaCost line) while its other citation for the same file (`:12`
  for the id) matches exactly. Fetch the cited file, cite the verified lines,
  and file the inherited citation for correction instead of copying it.
  (2026-10-20, paladin HUD band)
- **count the NAMES in an unpack, not the values you expect.** `pcall(f, …)`
  yields status + f's returns; a `local ok, a, _, b, _, _, _, id = pcall(f)`
  with an 8-name list over a 7-return API is CORRECT (8 = 1 + 7). An audit
  read it as 9 names and called it an off-by-one; the tree's own convention
  (`compat.lua:157-176` — 7 returns) settled it, and the suite it claimed
  would fail passed (1095/0). **When an audit contradicts the harness, run
  the one suite it names before dispatching a fix.** (2026-10-20, final gate)
- **a URL that 404s is a probe error until you check the path.** A lane
  reported the wowsims corpus "unverifiable" after fetching
  `github.com/wago-io/wowsims` — the org is `wowsims`
  (`wowsims/classic`, `wowsims/sod`, `wowsims/tbc-new`, `wowsims/forever`,
  `wowsims/wotlk`); `raw.githubusercontent.com/wowsims/classic/master/sim/core/rage.go`
  returns 200 and matched the cited numbers exactly. The strongest id evidence
  is still the CLIENT's own data (`/home/sam/wow.export` = the 1.15.9 SoD
  client) and warcraftdb's per-expansion domains. (2026-10-20, final gate)
- **ast-grep can see what read/grep cannot.** `read`/`grep` against
  `/home/sam/wow-ui-source` return `permission.rejected: external_directory`
  in a read-only lane, but `ast_grep_search` traverses it (51 matches across
  20 files on a pattern sweep). A report saying "the reference repo is not
  readable" is a tool-choice mistake, not a fact. **It cannot see a string
  literal inside a table constructor** — that is how a real citation got
  "refuted" once. (2026-10-20, AGENTS.md lane note)
- **one writer per file, always — including `tests/run.sh` and the TOCs.**
  Two lanes in one wave each needed a `run.sh` line and neither could own the
  file; the orchestrator took it and added both lines after they reported
  them. Same for the class suites: a lane that needs a pin in a file another
  lane owns must FILE the pin, not edit. (2026-10-20)
- **a rotation is the APL's SPELL rows; the pre-pull rows live in their own
  table.** Every fetched APL mixes spell rows with sim-harness rows
  (`autocastOtherCooldowns`, trinket/potion groups) and pre-pull rows (Charge,
  Aspect of the Hawk, Sanctity Aura). HU-12: the rotation table carries the
  spell rows; the pre-pull rows go to a per-class prepull table. A rotation
  that only carries the damage abilities is not the class's rotation — the
  utility layer belongs in the table too. (2026-10-20)
- **a hold is a decision; unknown is not.** The class must state its holds
  explicitly (`{ action = nil, hold = true }`), because "the guide wants
  nothing" and "the guide could not decide" are different facts — and one of
  them must be able to punish a wrong press. A neutral action (a legal
  non-rotation press) records no attempt, so idling cannot farm points.
  (2026-10-20, HU-8)
- **offer only what can be right.** An ability may only be offered on a
  family where it is rotation-ranked or neutral: a button that can only be a
  mis-pick is a trap. The offer gate, the closed-list test and the grader
  must all normalise the class's alias key space the same way, or a correct
  press grades F. (2026-10-20)
- **the Lua 5.1 local ceiling is a LOAD failure, not a test failure.** 200
  file-scope locals per chunk: one more `local` and the file does not load,
  on every client. `classes/paladin.lua` and `classes/warrior.lua` reached
  200/200; `classes/shaman.lua` and `practice_ui.lua` sit at 199. New state
  goes on the module table (`ST.<CLASS>.*` / `ui.*`), never a file-scope
  local. (2026-10-20)
- **a mutation copy of the tree is 278 MB — copy WITHOUT `Media/`.** Each
  copy of the repo carries the 187 MB media tree, so 74 leftover copies
  filled a 16 GB `/tmp` to 96% and would have broken every following lane
  mid-wave. Copy the sources, not the package: `rsync -a --exclude=Media
  --exclude=docs --exclude=.git`. **And clean `/tmp/opencode` between
  waves** — a full tmpfs is a silent, tree-wide failure that looks like
  "the lanes are broken". (2026-10-20)
- **the local-count guard uses the compiler's own count.** `luac5.1 -l -l`
  reports the chunk's active locals (counting NAMES, not lines — a
  `local a, b` line moves a file by two), so the guard cannot drift from
  a refactor the way a source-scan can. `tests/toc_check.lua` now fails
  above 190 file-scope locals per addon module and prints every file's
  count + headroom. (2026-10-20)

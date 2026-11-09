# Brief: secret-hole-closure — shaman/druid nil-break hardening (oracle R2 remainder)
Date: 2026-10-17. Orchestrator-issued. Source: bench/buildout_oracle-fixes_2026-10-17.md §1 + §7 (out-of-scope remainder with exact lines).

## Read first
desks/oracle-fixes/journal.md · bench/buildout_oracle-fixes_2026-10-17.md §1 (the applied R2 pattern) · bench/lessons.md · CAIRN.md

## Scope — writable files (hard boundary)
classes/shaman.lua (lines ~444, ~1263 ONLY), classes/druid.lua (lines ~560, ~608 ONLY), tests/shaman_state.lua, tests/druid_state.lua. NOTHING else — NOT tests/druid_guide_state.lua (~66k checks, do not touch).

## Task
Apply the proven R2 pattern to the 4 remaining nil-break loops: full-cap walk, nil = "no match at this index", no early break on unreadable rows; early-return-on-match preserved so existing read-count pins hold. Add secret-hole fixtures to both suites (secret row above the target entry → still found). If any of the 4 sites is NOT a scan loop on re-read (line drift), report it unmodified with evidence — do not force the pattern where it doesn't fit.

## Rules
Wire-not-strip; never `_`. No git, no lint-config, endings preserved (CRLF addon files, LF suites). Numeric/behavioral paths otherwise byte-identical.

## Validation
bash tests/run.sh → 35 steps, 0 failed. luacheck 0 errors, still 2 KEEP-ruled. Mutation proof on /tmp/opencode copy (restore one break → its hole pin FAILs).

## Deliverables
Code · desks/oracle-fixes/journal.md follow-up entry · signal JSON · bench/buildout_secret-hole_2026-10-17.md (per-loop: fix + evidence; or unmodified-with-reason). Final reply ≤6 lines. NEVER run git.

# Brief: hud-reflow — hidden-slot row reflow (gap closure)
Date: 2026-10-17. Orchestrator-issued. Owner: "anything that needs to be fixed for everything function properly, complete it now."

## Read first (all verified on disk)
desks/hud/journal.md · desks/journal.md · bench/buildout_hud-grade_2026-10-17.md §1 (the hide fix), §2 (slot tables), §5 finding #2 (the deferred reflow + the suggested shape + why it was NOT done) · bench/lessons.md · CAIRN.md

## Scope — writable files (hard boundary)
hud.lua + tests/hud_state.lua (reconcile is DONE — you own both file and pins now; keep them consistent). NOTHING else.

## Task — close hud-grade §5 finding #2
Layout counts `wanted`, not liveness, so a provider-hidden slot leaves a gap until a settings change reflows. Implement reflow-on-hidden-flip following the lane's weighed shape: track last hidden state per icon; on flip, reflow the row widths/counts; **defer while in combat** (lockdown — queue and apply on combat exit). Constraints (BINDING — these are why it was deferred): preserve the HS §5 exactly-once provider pin (no extra provider calls); preserve the at-most-once-per-tick-per-slot update contract; combat-safe (Show/Hide + reposition on non-secure row frames only, creation stays lockdown-gated as today).
Update tests/hud_state.lua pins to the new verified behavior (width/count expectations move — that is this lane's ownership now, not a reconcile violation). Extend, never weaken: every existing behavioral pin stays green.

## Rules
Wire-not-strip; never `_`. No git, no lint-config, endings preserved (hud.lua is CRLF — verify). Nil-safe throughout. No default-visible change beyond the intended gap closure (dead slots no longer reserve width). options-followup lane runs in parallel (its files are its own; it only reads hud.lua).

## Validation
bash tests/run.sh → 35 steps, 0 failed expected. hud_state green with updated pins. luacheck 0 errors. Mutation proofs on /tmp/opencode copy (reflow suppression → gap returns, check fails; combat-deferral bypass → pin fails).

## Deliverables
Code · desks/hud/journal.md entry · signal JSON · bench/buildout_hud-reflow_2026-10-17.md (design, pin updates, combat-safety argument, UNCONFIRMED in-client items). Final reply ≤6 lines. NEVER run git.

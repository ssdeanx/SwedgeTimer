#!/usr/bin/env bash
# Repo verification: Lua 5.1 syntax check, smoke test, toc check, luacheck.
# Usage: bash tests/run.sh   (run from anywhere; it cd's to the repo root)
# Runs every step even if one fails; exits 1 if any step failed.

set -u

cd "$(dirname "$0")/.." || exit 1

logdir=$(mktemp -d "${TMPDIR:-/tmp}/swedgetimer-tests.XXXXXX") || exit 1
trap 'rm -rf "$logdir"' EXIT

steps=0
failed=0

# run <name> <command...>: PASS on exit 0, FAIL otherwise; a failing step's log
# is printed instead of being swallowed.
run() {
    local name=$1
    shift
    local log="$logdir/step.log"
    local rc
    steps=$((steps + 1))
    if "$@" > "$log" 2>&1; then
        printf 'PASS  %s\n' "$name"
    else
        rc=$?
        failed=$((failed + 1))
        printf 'FAIL  %s (exit %d)\n' "$name" "$rc"
        if grep -q '^FAIL' "$log"; then
            # check-style output: show the failing checks, not the ok lines
            grep '^FAIL' "$log" | sed 's/^/      /'
            tail -n 3 "$log" | sed 's/^/      /'
        else
            sed 's/^/      /' "$log"
        fi
    fi
}

# luac5.1 -p on every addon .lua (repo root + classes/; Libs/ and docs/ excluded).
syntax_check() {
    local f rc=0
    for f in *.lua classes/*.lua; do
        if ! luac5.1 -p "$f"; then
            printf 'syntax error in %s\n' "$f"
            rc=1
        fi
    done
    return "$rc"
}

run "luac5.1 -p (root + classes .lua files)" syntax_check
run "lua5.1 tests/smoke.lua" lua5.1 tests/smoke.lua
run "lua5.1 tests/twist_state.lua" lua5.1 tests/twist_state.lua
run "lua5.1 tests/weave_state.lua" lua5.1 tests/weave_state.lua
run "lua5.1 tests/weave_range_state.lua" lua5.1 tests/weave_range_state.lua
run "lua5.1 tests/swing_source_state.lua" lua5.1 tests/swing_source_state.lua
run "lua5.1 tests/shaman_state.lua" lua5.1 tests/shaman_state.lua
run "lua5.1 tests/warrior_state.lua" lua5.1 tests/warrior_state.lua
run "lua5.1 tests/hunter_state.lua" lua5.1 tests/hunter_state.lua
run "lua5.1 tests/rogue_state.lua" lua5.1 tests/rogue_state.lua
run "lua5.1 tests/rogue_guide_state.lua" lua5.1 tests/rogue_guide_state.lua
run "lua5.1 tests/hunter_window_state.lua" lua5.1 tests/hunter_window_state.lua
run "lua5.1 tests/druid_energy_state.lua" lua5.1 tests/druid_energy_state.lua
run "lua5.1 tests/druid_state.lua" lua5.1 tests/druid_state.lua
run "lua5.1 tests/nextaction_state.lua" lua5.1 tests/nextaction_state.lua
run "lua5.1 tests/paladin_state.lua" lua5.1 tests/paladin_state.lua
run "lua5.1 tests/enemy_swing_state.lua" lua5.1 tests/enemy_swing_state.lua
run "lua5.1 tests/guide_contract.lua" lua5.1 tests/guide_contract.lua
run "lua5.1 tests/warrior_guide_state.lua" lua5.1 tests/warrior_guide_state.lua
run "lua5.1 tests/druid_guide_state.lua" lua5.1 tests/druid_guide_state.lua
run "lua5.1 tests/shaman_guide_state.lua" lua5.1 tests/shaman_guide_state.lua
run "lua5.1 tests/hunter_guide_state.lua" lua5.1 tests/hunter_guide_state.lua
run "lua5.1 tests/practice_state.lua" lua5.1 tests/practice_state.lua
run "lua5.1 tests/practice_ui_state.lua" lua5.1 tests/practice_ui_state.lua
run "lua5.1 tests/bars_state.lua" lua5.1 tests/bars_state.lua
run "lua5.1 tests/hud_state.lua" lua5.1 tests/hud_state.lua
run "lua5.1 tests/rotationtext_state.lua" lua5.1 tests/rotationtext_state.lua
run "lua5.1 tests/design_state.lua" lua5.1 tests/design_state.lua
run "lua5.1 tests/designmode_state.lua" lua5.1 tests/designmode_state.lua
run "lua5.1 tests/diag_state.lua" lua5.1 tests/diag_state.lua
run "lua5.1 tests/main_init_state.lua" lua5.1 tests/main_init_state.lua
run "lua5.1 tests/options_load_state.lua" lua5.1 tests/options_load_state.lua
run "lua5.1 tests/secret_guard_state.lua" lua5.1 tests/secret_guard_state.lua
run "lua5.1 tests/lrc_guard_state.lua" lua5.1 tests/lrc_guard_state.lua
run "lua5.1 tests/toc_check.lua" lua5.1 tests/toc_check.lua
run "lua5.1 tests/wiring_check.lua" lua5.1 tests/wiring_check.lua

# luacheck: exit 1 means warnings only, which is acceptable; exit >= 2 means errors.
steps=$((steps + 1))
log="$logdir/luacheck.log"
luacheck . --no-color > "$log" 2>&1
rc=$?
if [ "$rc" -le 1 ]; then
    total=$(grep -E '^Total:' "$log" | tail -n 1)
    printf 'PASS  luacheck . (%s)\n' "${total:-no summary}"
else
    failed=$((failed + 1))
    printf 'FAIL  luacheck . (exit %d)\n' "$rc"
    sed 's/^/      /' "$log"
fi

printf '\n%d steps, %d failed\n' "$steps" "$failed"
if [ "$failed" -gt 0 ]; then
    exit 1
fi
exit 0

#!/usr/bin/env bash
# Mutation proofs for the power-bar secret fix (powerbar-fix desk, 2026-11-06).
#
# Every case runs against an isolated copy of the sources + the two suites, so the
# pristine tree is never modified. A deliberately broken implementation must make the
# named suite fail (non-zero exit + FAIL lines) while the untouched copy passes.
#
# Usage: bash desks/powerbar-fix/run_mutations.sh   (from anywhere; SRC overrides repo)
set -u

SRC=${SRC:-/home/sam/SwedgeTimer}

# Copies the sources a suite needs into a fresh throwaway tree, runs it, reports.
# run_case <name> <suite> <python mutation code | empty for the pristine baseline>
run_case() {
    local name=$1 suite=$2 mutation=$3
    local work out rc fails
    work=$(mktemp -d /tmp/pb-mut.XXXXXX) || exit 1
    cp "$SRC"/*.lua "$work"/ || { echo "copy failed"; rm -rf "$work"; exit 1; }
    mkdir -p "$work/tests" || { rm -rf "$work"; exit 1; }
    cp "$SRC"/"$suite" "$work"/"$suite" || { rm -rf "$work"; exit 1; }
    if [ -n "$mutation" ]; then
        ( cd "$work" && python3 -c "$mutation" ) || {
            printf 'ERROR   %-38s mutation did not apply\n' "$name"
            rm -rf "$work"
            return 2
        }
    fi
    out=$( cd "$work" && lua5.1 "$suite" 2>&1 )
    rc=$?
    rm -rf "$work"
    if [ "$rc" -ne 0 ]; then
        fails=$(printf '%s\n' "$out" | grep -c '^FAIL' || true)
        printf 'KILL    %-38s %-32s exit=%d fails=%s\n' "$name" "$suite" "$rc" "$fails"
        printf '%s\n' "$out" | grep -E '^(FAIL|PASS)' | head -5 | sed 's/^/        /'
        return 0
    fi
    printf 'SURVIVED %-37s %-32s (suite passed - proof is worthless)\n' "$name" "$suite"
    return 1
}

killed=0
survived=0

# --- baseline: the pristine copy must pass both suites --------------------------------
baseline_check() {
    local suite=$1 work
    work=$(mktemp -d /tmp/pb-base.XXXXXX) || exit 1
    cp "$SRC"/*.lua "$work"/ || { rm -rf "$work"; exit 1; }
    mkdir -p "$work/tests" || { rm -rf "$work"; exit 1; }
    cp "$SRC"/"$suite" "$work"/"$suite" || { rm -rf "$work"; exit 1; }
    ( cd "$work" && lua5.1 "$suite" ) >/dev/null 2>&1
    local rc=$?
    rm -rf "$work"
    return "$rc"
}

echo "== baseline (pristine copy) =="
for suite in tests/power_bar_state.lua tests/forever_secret_compat_state.lua; do
    if baseline_check "$suite"; then
        printf 'PASS    baseline %-46s\n' "$suite"
    else
        printf 'BROKEN  baseline %s does not pass on its own\n' "$suite"
        exit 1
    fi
done
echo

# --- M1: compat nils the secret again (the original defect) --------------------------
M1='p="compat.lua"; s=open(p).read()
old="\treturn value, max_value, is_secret(value) or is_secret(max_value)\nend\n"
new="\tif is_secret(value) or is_secret(max_value) then return nil, nil, true end\n\treturn value, max_value, false\nend\n"
assert s.count(old) == 1, "anchor missing"
open(p,"w").write(s.replace(old,new,1))'
echo "== M1: GetPlayerPower nils a restricted value again =="
if run_case "M1_nil_the_secret_again" tests/forever_secret_compat_state.lua "$M1"; then
    killed=$((killed+1)); else survived=$((survived+1)); fi
echo

# --- M2: arithmetic on a restricted value (fraction) --------------------------------
M2='p="power_bar.lua"; s=open(p).read()
old="""        state.restricted = true
        state.value = value
        state.max_value = max_value
        return state
"""
new="""        state.restricted = true
        state.value = value
        state.max_value = max_value
        state.fraction = pb.fraction(value, max_value)
        return state
"""
assert s.count(old) == 1, "anchor missing"
open(p,"w").write(s.replace(old,new,1))'
echo "== M2: compute a fraction (arithmetic) on a restricted value =="
if run_case "M2_arithmetic_on_secret" tests/power_bar_state.lua "$M2"; then
    killed=$((killed+1)); else survived=$((survived+1)); fi
echo

# --- M2b: compare a restricted value (max_value <= 0 guard) --------------------------
M2B='p="power_bar.lua"; s=open(p).read()
old="        if type(value) ~= \"number\" or type(max_value) ~= \"number\" then\n            state.why = \"no-value\""
new="        if type(value) ~= \"number\" or type(max_value) ~= \"number\" or max_value <= 0 then\n            state.why = \"no-value\""
assert s.count(old) == 1, "anchor missing"
open(p,"w").write(s.replace(old,new,1))'
echo "== M2b: compare a restricted value (max <= 0) =="
if run_case "M2b_compare_on_secret" tests/power_bar_state.lua "$M2B"; then
    killed=$((killed+1)); else survived=$((survived+1)); fi
echo

# --- M3: hide the bar instead of painting it when restricted ------------------------
M3='p="power_bar.lua"; s=open(p).read()
old="""        frame.fill:SetMinMaxValues(0, state.max_value)
        frame.fill:SetValue(state.value)
        pb.last_value, pb.last_max_value = nil, nil
"""
new="""        frame.fill:SetMinMaxValues(0, state.max_value)
        frame.fill:SetValue(state.value)
        pb.last_value, pb.last_max_value = nil, nil
        return false
"""
assert s.count(old) == 1, "anchor missing"
open(p,"w").write(s.replace(old,new,1))'
echo "== M3: hide instead of show on a restricted read =="
if run_case "M3_hide_instead_of_show" tests/power_bar_state.lua "$M3"; then
    killed=$((killed+1)); else survived=$((survived+1)); fi
echo

# --- M4: format the restricted value for the label -----------------------------------
M4='p="power_bar.lua"; s=open(p).read()
old="local label = text_on and (state.restricted and \"?\" or pb.format_value(state.value)) or nil"
new="local label = text_on and pb.format_value(state.value) or nil"
assert s.count(old) == 1, "anchor missing"
open(p,"w").write(s.replace(old,new,1))'
echo "== M4: format a restricted value into the text =="
if run_case "M4_format_the_secret" tests/power_bar_state.lua "$M4"; then
    killed=$((killed+1)); else survived=$((survived+1)); fi
echo

# --- M5: weaken the arithmetic contract (UnitPower stops nil'ing a secret) ----------
M5='p="compat.lua"; s=open(p).read()
old="""	api.UnitPower = function(unit, power_type)
		local value = legacy_unit_power(unit, power_type)
		if is_secret(value) then
			return nil
		end
		return value
	end"""
new="""	api.UnitPower = function(unit, power_type)
		return legacy_unit_power(unit, power_type)
	end"""
assert s.count(old) == 1, "anchor missing"
open(p,"w").write(s.replace(old,new,1))'
echo "== M5: UnitPower leaks the secret to arithmetic consumers =="
if run_case "M5_contract_weakened" tests/forever_secret_compat_state.lua "$M5"; then
    killed=$((killed+1)); else survived=$((survived+1)); fi
echo

printf '%d/%d mutations killed\n' "$killed" "$((killed+survived))"
[ "$survived" -eq 0 ] || exit 1

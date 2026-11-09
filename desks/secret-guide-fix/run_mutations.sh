#!/usr/bin/env bash
# Mutation proofs for the secret-guide fix (2026-11-06).
#
# Every case runs against an isolated copy of the sources + the suite it targets, so the
# pristine tree is never modified. A deliberately broken implementation must make the
# named suite fail (non-zero exit + FAIL lines) while the untouched copy passes.
#
# Usage: bash desks/secret-guide-fix/run_mutations.sh   (from anywhere; SRC overrides)
set -u

SRC=${SRC:-/home/sam/SwedgeTimer}
SUITES="paladin_state hunter_state shaman_state druid_state warrior_state rogue_state \
forever_guide_state secret_guard_state"

run_case() {  # run_case <name> <suite> <python mutation code | empty for baseline>
    local name=$1 suite=$2 mutation=$3
    local work out rc fails
    work=$(mktemp -d /tmp/sg-mut.XXXXXX) || exit 1
    cp "$SRC"/*.lua "$SRC"/*.toc "$work"/ || { rm -rf "$work"; exit 1; }
    cp -a "$SRC"/classes "$SRC"/tests "$SRC"/Libs "$SRC"/bench "$work"/ || { rm -rf "$work"; exit 1; }
    if [ -n "$mutation" ]; then
        ( cd "$work" && python3 -c "$mutation" ) || {
            printf 'ERROR   %-40s mutation did not apply\n' "$name"
            rm -rf "$work"
            return 2
        }
    fi
    out=$( cd "$work" && lua5.1 "tests/$suite.lua" 2>&1 )
    rc=$?
    rm -rf "$work"
    if [ "$rc" -ne 0 ]; then
        fails=$(printf '%s\n' "$out" | grep -c '^FAIL' || true)
        printf 'KILL    %-40s %-20s exit=%d fails=%s\n' "$name" "$suite" "$rc" "$fails"
        printf '%s\n' "$out" | grep -E '^FAIL' | head -4 | sed 's/^/        /'
        return 0
    fi
    printf 'SURVIVED %-39s %-20s (suite passed - proof is worthless)\n' "$name" "$suite"
    return 1
}

baseline_check() {
    local suite=$1 work
    work=$(mktemp -d /tmp/sg-base.XXXXXX) || exit 1
    cp "$SRC"/*.lua "$SRC"/*.toc "$work"/ || { rm -rf "$work"; exit 1; }
    cp -a "$SRC"/classes "$SRC"/tests "$SRC"/Libs "$SRC"/bench "$work"/ || { rm -rf "$work"; exit 1; }
    ( cd "$work" && lua5.1 "tests/$suite.lua" ) >/dev/null 2>&1
    local rc=$?
    rm -rf "$work"
    return "$rc"
}

killed=0
survived=0

echo "== baseline (pristine copy, the seven suites) =="
for suite in $SUITES; do
    if baseline_check "$suite"; then
        printf 'PASS    baseline %-48s\n' "$suite"
    else
        printf 'BROKEN  baseline %s does not pass on its own\n' "$suite"
        exit 1
    fi
done
echo

# --- M1: the shared restricted-aware read ignores the restricted flag (H2 root) ------
M1='p="compat.lua"; s=open(p).read()
old="""	if restricted == true then
		return nil, nil, true
	end
"""
assert s.count(old) == 1, "anchor missing"
open(p,"w").write(s.replace(old,"",1))'
echo "== M1: api.get_cooldown_remaining treats a restricted read as ready =="
if run_case "M1_shared_helper_falls_through" paladin_state "$M1"; then killed=$((killed+1)); else survived=$((survived+1)); fi
echo

# --- M2: the hunter cooldown helper drops the fifth-return read ---------------------
M2='p="classes/hunter.lua"; s=open(p).read()
old="""    local remaining, duration, restricted = api.get_cooldown_remaining(query)
    if restricted == true then
        guide_reads_unknown = true
        return nil, nil
    end
"""
new="""    local remaining, duration = api.get_cooldown_remaining(query)
"""
assert s.count(old) == 1, "anchor missing"
open(p,"w").write(s.replace(old,new,1))'
echo "== M2: hunter cooldown helper drops the restricted read =="
if run_case "M2_hunter_drops_fifth_return" hunter_state "$M2"; then killed=$((killed+1)); else survived=$((survived+1)); fi
echo

# --- M3: the paladin gather drops the belt-and-braces unknown publication ----------
M3='p="classes/paladin.lua"; s=open(p).read()
old="""    if self.guide_reads_unknown == true then
        inputs.inputs_unknown = true
    end
"""
assert s.count(old) == 1, "anchor missing"
open(p,"w").write(s.replace(old,"",1))'
echo "== M3: a restricted tick no longer forces inputs_unknown =="
if run_case "M3_belt_dropped" paladin_state "$M3"; then killed=$((killed+1)); else survived=$((survived+1)); fi
echo

# --- M4: the paladin mana read falls back to 0 instead of unknown -------------------
M4='p="classes/paladin.lua"; s=open(p).read()
old="""    inputs.mana_pct = mana_pct"""
new="""    inputs.mana_pct = mana_pct or 0"""
assert s.count(old) == 1, "anchor missing"
open(p,"w").write(s.replace(old,new,1))'
echo "== M4: a restricted mana read is restored to 0 % =="
if run_case "M4_mana_or_zero" paladin_state "$M4"; then killed=$((killed+1)); else survived=$((survived+1)); fi
echo

# --- M5: the paladin JotC aura probe is dropped (H4) --------------------------------
M5='p="classes/paladin.lua"; s=open(p).read()
old="""            if may == true then
                self.guide_jotc_restricted = true
            end
"""
assert s.count(old) == 1, "anchor missing"
open(p,"w").write(s.replace(old,"",1))'
echo "== M5: the paladin JotC aura probe is dropped =="
if run_case "M5_paladin_aura_probe_dropped" paladin_state "$M5"; then killed=$((killed+1)); else survived=$((survived+1)); fi
echo

# --- M6: the warrior Rend aura probe is dropped (H4) --------------------------------
M6='p="classes/warrior.lua"; s=open(p).read()
old="""        if may == true then
            guide_reads_unknown = true
        end
"""
assert s.count(old) == 1, "anchor missing"
open(p,"w").write(s.replace(old,"",1))'
echo "== M6: the warrior Rend aura probe is dropped =="
if run_case "M6_warrior_aura_probe_dropped" warrior_state "$M6"; then killed=$((killed+1)); else survived=$((survived+1)); fi
echo

# --- M7: the druid target-debuff probe is dropped (H4) ------------------------------
M7='p="classes/druid.lua"; s=open(p).read()
old="""        if druid_debuff_found[key] ~= true and debuff_aura_may_be_secret(key) then
            guide_reads_unknown = true
        end
"""
assert s.count(old) == 1, "anchor missing"
open(p,"w").write(s.replace(old,"",1))'
echo "== M7: the druid Rip/Rake aura probe is dropped =="
if run_case "M7_druid_aura_probe_dropped" druid_state "$M7"; then killed=$((killed+1)); else survived=$((survived+1)); fi
echo

# --- M8: the shaman Flame Shock probe is dropped (H4) -------------------------------
M8='p="classes/shaman.lua"; s=open(p).read()
old="""		if may == true then
			ST.SHAMAN.guide_reads_unknown = true
		end
"""
assert s.count(old) == 1, "anchor missing"
open(p,"w").write(s.replace(old,"",1))'
echo "== M8: the shaman Flame Shock aura probe is dropped =="
if run_case "M8_shaman_aura_probe_dropped" shaman_state "$M8"; then killed=$((killed+1)); else survived=$((survived+1)); fi
echo

# --- M10: the paladin filler mirror compares the (now nil-able) mana again -----------
M10='p="classes/paladin.lua"; s=open(p).read()
old="    local mana_known = type(inputs.mana_pct) == \"number\""
new="    local mana_known = true"
assert s.count(old) == 1, "anchor missing"
open(p,"w").write(s.replace(old,new,1))'
echo "== M10: the paladin mana gate is dropped (nil compare) =="
if run_case "M10_paladin_mana_gate_dropped" secret_guard_state "$M10"; then killed=$((killed+1)); else survived=$((survived+1)); fi
echo

# --- M9: the engine stops honouring the caller's unknown bit ------------------------
M9='p="forever_guide.lua"; s=open(p).read()
old="""    out.inputs_unknown = raw_inputs.inputs_unknown == true"""
new="""    out.inputs_unknown = false"""
assert s.count(old) == 1, "anchor missing"
open(p,"w").write(s.replace(old,new,1))'
echo "== M9: the Forever engine ignores the gather's unknown bit =="
if run_case "M9_engine_ignores_unknown" forever_guide_state "$M9"; then killed=$((killed+1)); else survived=$((survived+1)); fi
echo

printf '%d/%d mutations killed\n' "$killed" "$((killed+survived))"
[ "$survived" -eq 0 ] || exit 1

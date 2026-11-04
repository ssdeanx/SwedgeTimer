-- tests/forever_guide_gate_state.lua: the Next Action Guide's Forever-only known-spell gate
-- (nextaction_ui.lua slot_known_allows): a confirmed-unlearned slot draws nothing, every
-- other family / slot shape / unanswerable client keeps the icon.
local script_dir = (arg[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
local ROOT = os.getenv("SWEDGE_ROOT") or (script_dir .. "/../")

local checks, failures = 0, 0
local function eq(got, want, label)
    checks = checks + 1
    if got ~= want then
        failures = failures + 1
        print("FAIL  " .. label .. "  (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
    end
end

local known = {}
local state_answers = true
local st = {
    family = "FOREVER",
    guard = { label = function() end },
    api = {
        GetSpellInfo = function(q) return type(q) == "string" and q or ("Spell" .. tostring(q)) end,
        is_spell_known_state = function(spell, fallback)
            if not state_answers then return false, "unknown" end
            if known[spell] or (fallback and known[fallback]) then return true, "known" end
            return false, "not_known"
        end,
    },
}
_G.CreateFrame = function() return {} end
_G.UIParent = {}
_G.LibStub = function(major)
    if major == "AceAddon-3.0" then return { GetAddon = function() return st end } end
    return {}
end

local chunk = assert(loadfile(ROOT .. "nextaction_ui.lua"))
chunk("SwedgeTimer", st)
local allows = st.nextaction_ui.slot_known_allows
eq(type(allows), "function", "ui.slot_known_allows exported")

local slot = { key = "holy_strike", spell_id = 679, spell_name = "Holy Strike", ids = { 679, 678, 1866 } }
eq(allows(slot), false, "forever: unlearned ranked slot is hidden")
known[1866] = true
eq(allows(slot), true, "forever: a later learned rank shows the slot")
known[1866] = nil
state_answers = false
eq(allows(slot), true, "forever: an unanswerable client keeps the icon (fail-visible)")
state_answers = true
eq(allows({ key = "twist", spell_id = 20375 }), true, "forever: slot without a rank table is never gated")
eq(allows(nil), true, "nil slot allowed")
st.family = "ERA"
eq(allows(slot), true, "other families are never gated")

if failures > 0 then
    print(string.format("FAIL  forever_guide_gate_state.lua (%d failures / %d checks)", failures, checks))
    os.exit(1)
end
print(string.format("PASS  forever_guide_gate_state.lua (%d checks)", checks))

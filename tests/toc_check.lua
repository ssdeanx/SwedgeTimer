-- TOC check: validates every repo-root SwedgeTimer*.toc (base + flavor variants).
-- docs/swedge/*.toc are archived addons and are deliberately not touched.
-- For each toc: every listed path exists, matched case-sensitively against the
-- real directory entries (a plain existence check would let case typos like the
-- historic AceEVent-3.0.xml through on case-sensitive loaders); no path is
-- listed twice; compat.lua is listed before main.lua; main.lua is listed; the
-- ## Interface header parses to one or more comma-separated numbers; and every
-- root/class module on disk is listed.
-- Plain Lua 5.1, no WoW client needed. Run from the repo root: lua5.1 tests/toc_check.lua
-- (the repo root is derived from this script's own location, so any cwd works).

local script_dir = (arg[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
local ROOT = script_dir .. "/../"

local checks, failures = 0, 0
local function check(cond, label)
    checks = checks + 1
    if cond then
        print("ok   " .. label)
    else
        failures = failures + 1
        print("FAIL " .. label)
    end
end

-- ---------------------------------------------------------------------------
-- Filesystem helpers
-- ---------------------------------------------------------------------------

-- io.popen is required so matching stays case-sensitive on any filesystem.
check(io.popen ~= nil, "io.popen is available for directory listings")

local function shell_lines(cmd)
    if not io.popen then return {} end
    local pipe = io.popen(cmd)
    if not pipe then return {} end
    local lines = {}
    for line in pipe:lines() do
        lines[#lines + 1] = line
    end
    pipe:close()
    return lines
end

-- Cache of directory entries, straight from `ls` so names keep their case.
local dir_cache = {}
local function dir_entries(dir)
    if dir_cache[dir] == nil then
        local entries = {}
        for _, name in ipairs(shell_lines('ls -A -- "' .. dir .. '" 2>/dev/null')) do
            entries[name] = true
        end
        dir_cache[dir] = entries
    end
    return dir_cache[dir]
end

local function disk_case_match(dir, name)
    local lower = name:lower()
    for entry in pairs(dir_entries(dir)) do
        if entry:lower() == lower then
            return entry
        end
    end
    return nil
end

-- nil when a toc path (backslash separated) resolves case-sensitively, else a reason.
local function path_problem(path)
    local dir = ROOT
    for segment in path:gmatch("[^\\/]+") do
        if not dir_entries(dir)[segment] then
            local actual = disk_case_match(dir, segment)
            if actual then
                return string.format('case mismatch: disk has "%s"', actual)
            end
            return string.format('missing under "%s"', dir)
        end
        dir = dir .. segment .. "/"
    end
    return nil
end

-- .lua files on disk as toc-style paths (backslash separated), sorted.
local function lua_files_on_disk(dir, prefix)
    local files = {}
    for name in pairs(dir_entries(dir)) do
        if name:match("%.lua$") then
            files[#files + 1] = prefix .. name
        end
    end
    table.sort(files)
    return files
end

-- ---------------------------------------------------------------------------
-- What every toc must list, and which tocs to check
-- ---------------------------------------------------------------------------

local root_modules = lua_files_on_disk(ROOT, "")
local class_modules = lua_files_on_disk(ROOT .. "classes/", "classes\\")
check(#root_modules > 0, "repo root has .lua modules to account for")
check(#class_modules > 0, "classes/ has .lua modules to account for")

local tocs = {}
for _, path in ipairs(shell_lines('ls -1 "' .. ROOT .. '"SwedgeTimer*.toc 2>/dev/null')) do
    tocs[#tocs + 1] = path:match("([^/]+)$") or path
end
table.sort(tocs)
check(#tocs > 0, "repo root has SwedgeTimer*.toc files")

-- ---------------------------------------------------------------------------
-- Per-toc checks
-- ---------------------------------------------------------------------------

-- Captured per toc so the matrix-level family invariants after the loop can be checked:
-- toc_values[toc] = set of ## Interface values; toc_lists[toc] = set of listed paths.
local toc_values, toc_lists = {}, {}

-- F10: the shared error-isolation contract (guard.lua) must load before every module
-- that uses it - a missing or late line is a silent runtime no-op (the consumer would
-- find no st.guard when it loads).
local GUARD_CONSUMERS = {
    "bars.lua", "nextaction_ui.lua", "practice_ui.lua", "hud.lua", "rotationtext.lua",
}

-- The shared font chain (utils.lua: st.utils.apply_font / st.utils.fetch_font_path)
-- must load before every module that fonts a FontString through it - a consumer that
-- loads first would find no helper and its FontStrings would go out without a font.
local FONT_CONSUMERS = {
    "bars.lua", "hunter_ui.lua", "practice_ui.lua", "designmode.lua",
    "nextaction_ui.lua", "classes\\rogue.lua",
}

for _, toc in ipairs(tocs) do
    local entries, interface_text = {}, nil
    local file = io.open(ROOT .. toc, "r")
    if not file then
        check(false, toc .. ": readable")
    else
        for line in file:lines() do
            line = line:gsub("\r$", "")
            if interface_text == nil then
                interface_text = line:match("^##%s*Interface:%s*(.-)%s*$")
            end
            local trimmed = line:match("^%s*(.-)%s*$")
            if trimmed ~= "" and trimmed:sub(1, 1) ~= "#" then
                entries[#entries + 1] = trimmed
            end
        end
        file:close()

        -- ## Interface: one or more comma-separated numbers
        local interface_ok = false
        if interface_text then
            interface_ok = true
            local values = 0
            for value in interface_text:gmatch("[^,]+") do
                values = values + 1
                if not value:match("^%s*%d+%s*$") then
                    interface_ok = false
                end
            end
            interface_ok = interface_ok and values > 0
        end
        local interface_label = toc .. ": ## Interface parses to numbers"
        if not interface_text then
            interface_label = interface_label .. " (header missing)"
        elseif not interface_ok then
            interface_label = interface_label .. ' (bad value "' .. interface_text .. '")'
        end
        check(interface_ok, interface_label)

        local interface_values = {}
        if interface_text then
            for value in interface_text:gmatch("[^,]+") do
                interface_values[value:match("^%s*(.-)%s*$")] = true
            end
        end
        toc_values[toc] = interface_values

        -- every listed path exists, case-sensitively
        for _, entry in ipairs(entries) do
            local problem = path_problem(entry)
            check(problem == nil,
                toc .. ": " .. entry .. " exists" .. (problem and (" (" .. problem .. ")") or ""))
        end

        -- no duplicate entries
        local seen, duplicates = {}, {}
        for _, entry in ipairs(entries) do
            if seen[entry] then
                duplicates[#duplicates + 1] = entry
            end
            seen[entry] = true
        end
        check(#duplicates == 0,
            toc .. ": no duplicate entries" ..
            (#duplicates > 0 and (" (duplicates: " .. table.concat(duplicates, ", ") .. ")") or ""))
        toc_lists[toc] = seen

        -- compat.lua before main.lua (covers that both are listed)
        local compat_index, main_index
        for i, entry in ipairs(entries) do
            if entry == "compat.lua" and compat_index == nil then compat_index = i end
            if entry == "main.lua" and main_index == nil then main_index = i end
        end
        check(compat_index and main_index and compat_index < main_index,
            toc .. ": compat.lua before main.lua")

        -- F10: guard.lua after utils.lua and before every consumer of the contract.
        local guard_index, utils_index = nil, nil
        local consumer_at = {}
        for i, entry in ipairs(entries) do
            if entry == "guard.lua" and guard_index == nil then guard_index = i end
            if entry == "utils.lua" and utils_index == nil then utils_index = i end
            for _, consumer in ipairs(GUARD_CONSUMERS) do
                if entry == consumer then consumer_at[consumer] = i end
            end
            for _, consumer in ipairs(FONT_CONSUMERS) do
                if entry == consumer then consumer_at[consumer] = i end
            end
        end
        check(guard_index ~= nil, toc .. ": lists guard.lua (the shared isolation contract)")
        check(utils_index ~= nil and guard_index ~= nil and utils_index < guard_index,
            toc .. ": guard.lua loads after utils.lua")
        local late = {}
        for _, consumer in ipairs(GUARD_CONSUMERS) do
            local at = consumer_at[consumer]
            if at == nil or (guard_index ~= nil and at < guard_index) then
                late[#late + 1] = consumer
            end
        end
        check(#late == 0, toc .. ": guard.lua loads before every consumer" ..
            (#late > 0 and (" (too late: " .. table.concat(late, ", ") .. ")") or ""))

        -- The shared font chain (utils.lua) loads before every module that fonts a
        -- FontString through it.
        local font_late = {}
        for _, consumer in ipairs(FONT_CONSUMERS) do
            local at = consumer_at[consumer]
            if at == nil or (utils_index ~= nil and at < utils_index) then
                font_late[#font_late + 1] = consumer
            end
        end
        check(#font_late == 0, toc .. ": utils.lua loads before every font consumer" ..
            (#font_late > 0 and (" (too late: " .. table.concat(font_late, ", ") .. ")") or ""))

        -- P9 load order: swing_source.lua needs compat's st.family/st.api and must load
        -- before main.lua (which reads st.swing_source while it loads); weave.lua is pure
        -- and loads before main.lua; class modules load after main.lua. The rogue's pure
        -- guide (rogue_guide.lua) loads with the other guide modules, before practice.lua
        -- and main.lua consume it; the class module loads after the warrior (the class
        -- block's established tail).
        local swing_source_index, weave_index, twist_index, shaman_index
        local hunter_guide_index, rogue_guide_index, practice_index, warrior_index, rogue_index
        for i, entry in ipairs(entries) do
            if entry == "swing_source.lua" and swing_source_index == nil then swing_source_index = i end
            if entry == "weave.lua" and weave_index == nil then weave_index = i end
            if entry == "twist.lua" and twist_index == nil then twist_index = i end
            if entry == "classes\\shaman.lua" and shaman_index == nil then shaman_index = i end
            if entry == "hunter_guide.lua" and hunter_guide_index == nil then hunter_guide_index = i end
            if entry == "rogue_guide.lua" and rogue_guide_index == nil then rogue_guide_index = i end
            if entry == "practice.lua" and practice_index == nil then practice_index = i end
            if entry == "classes\\warrior.lua" and warrior_index == nil then warrior_index = i end
            if entry == "classes\\rogue.lua" and rogue_index == nil then rogue_index = i end
        end
        check(compat_index and swing_source_index and swing_source_index > compat_index
                and main_index and swing_source_index < main_index,
            toc .. ": compat.lua before swing_source.lua before main.lua")
        check(twist_index and weave_index and main_index
                and twist_index < weave_index and weave_index < main_index,
            toc .. ": twist.lua before weave.lua before main.lua")
        check(shaman_index and main_index and shaman_index > main_index,
            toc .. ": classes\\shaman.lua loads after main.lua")
        check(hunter_guide_index and rogue_guide_index and practice_index and main_index
                and rogue_guide_index > hunter_guide_index
                and rogue_guide_index < practice_index and rogue_guide_index < main_index,
            toc .. ": rogue_guide.lua sits in the guide group before practice.lua/main.lua")
        check(warrior_index and rogue_index and rogue_index > warrior_index,
            toc .. ": classes\\rogue.lua loads after classes\\warrior.lua")

        -- every addon .lua module on disk is listed
        for _, module_path in ipairs(root_modules) do
            check(seen[module_path] == true, toc .. ": lists " .. module_path)
        end
        for _, module_path in ipairs(class_modules) do
            check(seen[module_path] == true, toc .. ": lists " .. module_path)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Family invariants: pin the intended per-flavour divergence
-- ---------------------------------------------------------------------------
-- The universal build branches on family at runtime; what actually differs per toc is
-- which files load and which clients it advertises (see AGENTS.md "Cross-engine"). A
-- wrong engine library or a dropped module line is a silent runtime no-op, so both
-- directions are pinned here.

local LCTA = "Libs\\LibClassicSwingTimerAPI\\LibClassicSwingTimerAPI.lua"

-- LibClassicSwingTimerAPI: classic-line engines only. Its spell tables stay nil on
-- Cata/Mists and Mainline has no classic combat log at all (swing_source.lua on Forever,
-- the inert stand-in on Retail), so shipping it there - or dropping it from a classic-line
-- toc - is wrong in both directions.
local LCTA_TOCS = {
    ["SwedgeTimer_Vanilla.toc"] = true,
    ["SwedgeTimer_TBC.toc"] = true,
    ["SwedgeTimer_Wrath.toc"] = true,
}
local FLAVOR_TOCS = {
    "SwedgeTimer_Vanilla.toc", "SwedgeTimer_TBC.toc", "SwedgeTimer_Wrath.toc",
    "SwedgeTimer_Mainline.toc", "SwedgeTimer_Cata.toc", "SwedgeTimer_Mists.toc",
}
for _, toc in ipairs(FLAVOR_TOCS) do
    check(toc_lists[toc] ~= nil, toc .. ": exists and was checked")
    local ships = toc_lists[toc] ~= nil and toc_lists[toc][LCTA] == true
    local should_ship = LCTA_TOCS[toc] == true
    check(ships == should_ship, toc .. (should_ship
        and ": ships LibClassicSwingTimerAPI (classic swing engine)"
        or ": does not ship LibClassicSwingTimerAPI (Mainline stand-in / Cata-Mists nil tables)"))
end

-- ## Interface matrix: each flavour advertises EXACTLY its client (the base toc is the
-- classic-line fallback only, Mainline owns Retail/Forever), and WotLK Classic (30401) is
-- not a supported target.
local INTERFACE_EXACT = {
    { toc = "SwedgeTimer_Vanilla.toc", values = { "11509" } },
    { toc = "SwedgeTimer_TBC.toc", values = { "20506" } },
    { toc = "SwedgeTimer_Wrath.toc", values = { "38002" } },
    { toc = "SwedgeTimer_Mainline.toc", values = { "120100", "120105", "16001" } },
    -- The base toc is the classic-line FALLBACK only: it ships
    -- LibClassicSwingTimerAPI, whose file-scope RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    -- throws on mainline-code clients (no classic combat log there) and would abort the
    -- whole addon load. It therefore advertises NO mainline interface. This is an EXACT
    -- check, not a contains check: the F6 regression (2026-10-25) re-added 120105/120107/
    -- 16001 and passed a contains-only loop, which is the hole this table closes.
    { toc = "SwedgeTimer.toc", values = { "11509", "20506", "38002" } },
}
local INTERFACE_CONTAINS = {}
local function interface_list(toc)
    local values = {}
    for value in pairs(toc_values[toc] or {}) do values[#values + 1] = value end
    table.sort(values)
    return (#values > 0) and table.concat(values, ", ") or "(missing/unparsable)"
end
for _, spec in ipairs(INTERFACE_EXACT) do
    local want, got = {}, toc_values[spec.toc] or {}
    local same, seen_count = true, 0
    for i = 1, #spec.values do want[spec.values[i]] = true end
    for value in pairs(got) do
        seen_count = seen_count + 1
        if not want[value] then same = false end
    end
    if seen_count ~= #spec.values then same = false end
    check(same, spec.toc .. ": ## Interface is exactly " .. table.concat(spec.values, ", ")
        .. " (got: " .. interface_list(spec.toc) .. ")")
end
for _, spec in ipairs(INTERFACE_CONTAINS) do
    local got = toc_values[spec.toc] or {}
    local missing = {}
    for i = 1, #spec.values do
        if not got[spec.values[i]] then missing[#missing + 1] = spec.values[i] end
    end
    check(#missing == 0, spec.toc .. ": ## Interface advertises " .. table.concat(spec.values, ", ")
        .. " (missing: " .. ((#missing > 0) and table.concat(missing, ", ") or "none") .. ")")
end
for _, toc in ipairs(tocs) do
    check(not (toc_values[toc] and toc_values[toc]["30401"]),
        toc .. ": does not advertise Interface 30401 (WotLK Classic is not a supported target)")
end

-- Newest standalone modules / class modules: a missing toc line is a silent no-op at
-- runtime, and removing module and line together would slip past the disk-completeness
-- check above, so the names are pinned explicitly on every toc.
local REQUIRED_MODULES = {
    "diag.lua", "hunter_window.lua", "power_bar.lua", "rogue_guide.lua", "classes\\rogue.lua",
}
for _, toc in ipairs(tocs) do
    for _, module_path in ipairs(REQUIRED_MODULES) do
        check(toc_lists[toc] ~= nil and toc_lists[toc][module_path] == true,
            toc .. ": lists " .. module_path .. " (newest module, required)")
    end
end

-- ---------------------------------------------------------------------------
-- The harness registry: every suite on disk is REGISTERED, and every registered
-- suite runs
-- ---------------------------------------------------------------------------
-- tests/run.sh is an explicit per-suite registry: a suite added without its
-- registry line yields a GREEN harness that never runs the new suite (this tree
-- has produced that accident once - the pre-pull contract suite existed
-- unregistered for a window). Both directions are pinned here, and the count is
-- pinned too: one registry line per suite, so a suite registered twice is caught
-- as well. This file is itself a registered step, so the check needs no new
-- registry line.

local suites_on_disk = {}
for name in pairs(dir_entries(ROOT .. "tests/")) do
    if name:match("%.lua$") then
        suites_on_disk[#suites_on_disk + 1] = "tests/" .. name
    end
end
table.sort(suites_on_disk)
check(#suites_on_disk > 0, "tests/ has .lua suites to account for")

local run_file = io.open(ROOT .. "tests/run.sh", "r")
local run_text = ""
if run_file then
    run_text = run_file:read("*a")
    run_file:close()
end
check(run_file ~= nil, "tests/run.sh is readable (the harness registry)")

-- The registered suites: every "tests/<name>.lua" token in the registry text.
local registered, registered_lines = {}, 0
for path in run_text:gmatch("tests/[%w_%-]+%.lua") do
    registered[path] = true
end
-- The registry lines: one "run "lua5.1 tests/..." line per suite.
for line in run_text:gmatch("[^\n]+") do
    if line:match('^run "lua5%.1 tests/') then
        registered_lines = registered_lines + 1
    end
end

local on_disk = {}
for _, suite in ipairs(suites_on_disk) do
    on_disk[suite] = true
end
local unregistered, missing = {}, {}
for _, suite in ipairs(suites_on_disk) do
    if registered[suite] ~= true then
        unregistered[#unregistered + 1] = suite
    end
end
for path in pairs(registered) do
    if on_disk[path] ~= true then
        missing[#missing + 1] = path
    end
end
table.sort(unregistered)
table.sort(missing)

check(#unregistered == 0,
    "every suite on disk is registered in tests/run.sh" ..
    (#unregistered > 0 and (" (unregistered: " .. table.concat(unregistered, ", ") .. ")") or ""))
check(#missing == 0,
    "every suite registered in tests/run.sh exists on disk" ..
    (#missing > 0 and (" (missing on disk: " .. table.concat(missing, ", ") .. ")") or ""))

local registered_count = 0
for _ in pairs(registered) do
    registered_count = registered_count + 1
end
check(registered_count == registered_lines,
    "tests/run.sh runs every registered suite exactly once (" ..
    registered_count .. " registered, " .. registered_lines .. " registry lines)")
check(registered_count == #suites_on_disk,
    "the registry and the suites on disk agree in number (" ..
    registered_count .. " registered, " .. #suites_on_disk .. " on disk)")

-- ---------------------------------------------------------------------------
-- The CHANGELOG's "per-class sets" passage is pinned against the tree
-- ---------------------------------------------------------------------------
-- WHY THIS EXISTS: the passage tells the reader which neutral action keys each
-- class publishes per family. It is true today, and it had to be repaired once
-- already (bench/stale_claims_2026-10-20.md §4 item 4 - the passage no longer
-- matched the tree and was rewritten). No suite read CHANGELOG.md, so the next
-- edit to the passage OR to a class's publish could make it false with a green
-- harness. This block is that reader.
--
-- WHAT IT CHECKS, per class:
--   * the keys the passage NAMES for the class are the keys the class PUBLISHES
--     (the union over the published families) - or, for the two classes whose
--     passage states only the key the tree drops, exactly that dropped key;
--   * every family the passage attaches to a key publishes that key, and every
--     family the passage excludes it from does NOT publish it;
--   * the "every family" keys are published on every published family;
--   * a flat publish is stated as flat, and a family-scoped publish as
--     family-scoped;
--   * the "no bucket for <families>" claim: the classes the passage names
--     publish no bucket for those families, and the others still answer every
--     family.
--
-- HOW THE PASSAGE IS PARSED: the class a key belongs to is the class named
-- before it (the bold class name or the possessive - "the hunter's without
-- `raptor`"), and the family a key is attached to is the list after the key
-- ("`battle_shout` on WotLK"). A qualifier at the end of a list covers the whole
-- list ("the common abilities `holy_light`, ..., `food` on Era, TBC, WotLK and
-- Forever"), and a "the same N keys" clause resolves to the list before it
-- minus the key the clause excludes.
-- ---------------------------------------------------------------------------
do
    -- The class, its file and HOW the passage states its set. The CONTENT is
    -- compared against the tree, not against this table: "list" means the
    -- passage enumerates the class's keys, "delta" means it names only the key
    -- the tree drops from some families ("the hunter's without `raptor`").
    local CLAIMS = {
        { class = "PALADIN", name = "paladin", file = "classes/paladin.lua", mode = "list" },
        { class = "WARRIOR", name = "warrior", file = "classes/warrior.lua", mode = "list" },
        { class = "ROGUE", name = "rogue", file = "classes/rogue.lua", mode = "list" },
        { class = "SHAMAN", name = "shaman", file = "classes/shaman.lua", mode = "list" },
        { class = "HUNTER", name = "hunter", file = "classes/hunter.lua", mode = "delta" },
        { class = "DRUID", name = "druid", file = "classes/druid.lua", mode = "delta" },
    }
    -- The family tokens the passage spells, mapped onto the tree's tokens.
    local FAMILY_TOKENS = {
        Era = "ERA", TBC = "TBC", WotLK = "WRATH", Wrath = "WRATH",
        Forever = "FOREVER", Cata = "CATA", Mists = "MISTS", Retail = "RETAIL",
    }
    local NUMBER_WORDS = {
        one = 1, two = 2, three = 3, four = 4, five = 5, six = 6, seven = 7,
        eight = 8, nine = 9, ten = 10, eleven = 11, twelve = 12,
    }
    local CLASS_BY_NAME = {}
    local CLASS_FILE = {}
    for _, claim in ipairs(CLAIMS) do
        CLASS_BY_NAME[claim.name] = claim.class
        CLASS_FILE[claim.class] = claim.file
    end

    local function read_file(path)
        local fh = io.open(path, "r")
        if not fh then
            return nil
        end
        local text = fh:read("*a")
        fh:close()
        return text
    end

    -- The passage: the "- **The per-class sets.**" bullet of CHANGELOG.md.
    local passage = nil
    local changelog = read_file(ROOT .. "CHANGELOG.md")
    check(changelog ~= nil, "CHANGELOG.md is readable (the per-class sets passage)")
    if changelog then
        local lines = {}
        local inside = false
        for line in (changelog:gsub("\r\n", "\n")):gmatch("([^\n]*)\n?") do
            if not inside then
                if line:match("^%-%s+%*%*The per%-class sets%.%*%*") then
                    inside = true
                    lines[#lines + 1] = line
                end
            elseif line:match("^%- ") then
                inside = false
            else
                lines[#lines + 1] = line
            end
        end
        passage = table.concat(lines, " ")
    end
    check(passage ~= nil and #passage > 0,
        "CHANGELOG.md carries the 'The per-class sets.' passage")

    -- The class mentions (the bold class name, the possessive and the plain
    -- "the <class>"), in order. The class a key belongs to is the class named
    -- before it; the plain mention only bounds the passage.
    local mentions = {}
    local first_mention = {}
    if passage then
        local pos = 1
        while true do
            local s, e, name = passage:find("%*%*([%a]+)%*%*", pos)
            if not s then break end
            local class = CLASS_BY_NAME[name:lower()]
            if class then
                mentions[#mentions + 1] = { pos = s, class = class }
            end
            pos = e + 1
        end
        pos = 1
        while true do
            local s, e, name = passage:find("the ([%a]+)'s", pos)
            if not s then break end
            local class = CLASS_BY_NAME[name:lower()]
            if class then
                mentions[#mentions + 1] = { pos = s, class = class }
            end
            pos = e + 1
        end
        pos = 1
        while true do
            local s, e, name = passage:find("the ([%a]+)", pos)
            if not s then break end
            local class = CLASS_BY_NAME[name:lower()]
            if class then
                mentions[#mentions + 1] = { pos = s, class = class }
            end
            pos = e + 1
        end
        table.sort(mentions, function(a, b) return a.pos < b.pos end)
        -- The first mention of each class: the text between it and the class's
        -- first key is the claim's lead ("(family-scoped - ...", "(flat - ...").
        for _, mention in ipairs(mentions) do
            if first_mention[mention.class] == nil then
                first_mention[mention.class] = mention.pos
            end
        end
        -- The per-class claims end with the sentence that names the last class:
        -- the rest of the bullet is the mechanism (the practice-panel ability
        -- list, the unknown-hides rule), not a per-class claim.
        local last = mentions[#mentions]
        if last then
            local stop = passage:find("%. ", last.pos)
            if stop then
                passage = passage:sub(1, stop)
            end
        end
    end

    -- The keys: the backticked tokens that are action keys, with the class named
    -- before them and the text around them.
    local keys = {}
    if passage then
        local pos = 1
        while true do
            local s, e, name = passage:find("`([%a_][%w_]*)`", pos)
            if not s then break end
            local class = nil
            local mention_pos = 0
            for _, mention in ipairs(mentions) do
                if mention.pos < s then
                    class = mention.class
                    mention_pos = mention.pos
                end
            end
            keys[#keys + 1] = { start = s, stop = e, name = name, class = class,
                mention_pos = mention_pos }
            pos = e + 1
        end
    end
    check(#keys > 0, "the passage names at least one action key")

    -- The family list after " on " (the tokens the passage spells), and whether
    -- the list is "every family".
    local function parse_family_list(text)
        local rest = text:match("^%s*on%s+(.*)$")
        if not rest then
            return nil, false
        end
        local families, every = {}, false
        for word in rest:gmatch("[%a]+") do
            if word == "every" then
                every = true
            elseif FAMILY_TOKENS[word] then
                families[FAMILY_TOKENS[word]] = true
            elseif word ~= "family" and word ~= "and" and word ~= "or" then
                -- the connector and the "every family" tail carry no family of
                -- their own; anything else ends the list.
                break
            end
        end
        return families, every
    end

    -- The published table: ST.<CLASS>.practice_neutral_actions - the family
    -- buckets and their keys, or a flat set.
    local function published_neutral(path, class)
        local src = read_file(path)
        if not src then
            return nil
        end
        src = src:gsub("\r\n", "\n")
        local families, flat = {}, {}
        local inside, depth, current = false, 0, nil
        for line in src:gmatch("[^\n]+") do
            if not inside then
                if line:find("ST%." .. class .. ".practice_neutral_actions%s*=%s*{") then
                    inside = true
                    depth = 1
                end
            else
                local code = line:gsub("%-%-.*$", "")
                local family = code:match("^%s*(%u[%u%d_]*)%s*=%s*{%s*$")
                if family then
                    depth = depth + 1
                    current = family
                    families[current] = {}
                else
                    local key = code:match("^%s*([%w_]+)%s*=%s*true,?%s*$")
                    if key then
                        if depth == 1 then
                            flat[key] = true
                        elseif current then
                            families[current][key] = true
                        end
                    elseif code:match("^%s*},?%s*$") then
                        depth = depth - 1
                        current = nil
                        if depth == 0 then
                            break
                        end
                    end
                end
            end
        end
        if next(flat) ~= nil then
            families.FLAT = flat
        end
        return families
    end

    local function set_to_list(set)
        local out = {}
        for key in pairs(set) do
            out[#out + 1] = key
        end
        table.sort(out)
        return out
    end

    local function same_set(a, b)
        for key in pairs(a) do
            if b[key] == nil then
                return false
            end
        end
        for key in pairs(b) do
            if a[key] == nil then
                return false
            end
        end
        return true
    end

    for _, claim in ipairs(CLAIMS) do
        local class = claim.class
        local published = published_neutral(ROOT .. claim.file, class)
        check(published ~= nil, class .. ": the published neutral table is readable")
        if published then
            -- the tree's own truth: the union over the published families, the
            -- keys every published family carries, and the keys some family drops.
            local union, shared = {}, {}
            local first = true
            for _, family in ipairs({ "ERA", "TBC", "WRATH", "FOREVER", "CATA", "MISTS", "RETAIL", "FLAT" }) do
                local bucket = published[family]
                if bucket then
                    for key in pairs(bucket) do union[key] = true end
                    if first then
                        for key in pairs(bucket) do shared[key] = true end
                        first = false
                    else
                        for key in pairs(shared) do
                            if bucket[key] == nil then shared[key] = nil end
                        end
                    end
                end
            end
            local dropped = {}
            for key in pairs(union) do
                if shared[key] == nil then dropped[key] = true end
            end

            -- the passage's claim for this class
            local named = {}
            for _, key in ipairs(keys) do
                if key.class == class then
                    named[key.name] = true
                end
            end
            if claim.mode == "list" then
                check(same_set(named, union),
                    class .. ": the passage names the class's published keys ("
                        .. table.concat(set_to_list(named), ", ") .. " vs the tree's "
                        .. table.concat(set_to_list(union), ", ") .. ")")
            else
                check(same_set(named, dropped),
                    class .. ": the passage names the key the class drops ("
                        .. table.concat(set_to_list(named), ", ") .. " vs the tree's "
                        .. table.concat(set_to_list(dropped), ", ") .. ")")
            end

            -- the shape of the publish: a flat publish is stated as flat.
            local shape = "family-scoped"
            if published.FLAT and next(published.FLAT) ~= nil and #set_to_list(union) > 0 then
                local only_flat = true
                for family in pairs(published) do
                    if family ~= "FLAT" then only_flat = false end
                end
                if only_flat then shape = "flat" end
            end
            local lead = nil
            local lead_pos = first_mention[class]
            if lead_pos then
                for _, key in ipairs(keys) do
                    if key.class == class then
                        lead = passage:sub(lead_pos, key.start - 1)
                        break
                    end
                end
            end
            if lead then
                check(lead:lower():find(shape, 1, true) ~= nil,
                    class .. ": the passage states the publish as " .. shape)
            end
        end
    end

    -- The "no bucket" claim: the classes the passage says publish NO bucket for
    -- the named families, and the ones it says still answer every family.
    if passage then
        local phrase = passage:lower():find("no bucket for ([%a, ]+)")
        check(phrase ~= nil,
            "the passage states which classes publish no bucket for which families")
        if phrase then
            local named_families = {}
            for word in passage:lower():match("no bucket for ([%a, ]+)"):gmatch("[%a]+") do
                local token = FAMILY_TOKENS[word:sub(1, 1):upper() .. word:sub(2)]
                    or FAMILY_TOKENS[word]
                if token then named_families[token] = true end
            end
            -- the class list: the names between the two dashes that follow the
            -- phrase ("... **no bucket for Cata, Mists or Retail** - the warrior,
            -- the rogue, the hunter and the druid - offer ...").
            local list = ""
            local dash_start = passage:find("\226\128\148", phrase)
            local dash_end = dash_start and passage:find("\226\128\148", dash_start + 3)
            if dash_start and dash_end then
                list = passage:sub(dash_start + 3, dash_end - 1)
            end
            local no_bucket = {}
            for name in list:gmatch("the ([%a]+)") do
                local class = CLASS_BY_NAME[name:lower()]
                if class then no_bucket[class] = true end
            end
            check(next(no_bucket) ~= nil,
                "the passage's 'no bucket' claim names the classes it applies to")
            for _, claim in ipairs(CLAIMS) do
                local published = published_neutral(ROOT .. claim.file, claim.class)
                if published then
                    local buckets = 0
                    for family in pairs(named_families) do
                        if published[family] then buckets = buckets + 1 end
                    end
                    if no_bucket[claim.class] then
                        check(buckets == 0,
                            claim.class .. ": the passage says it publishes no bucket for "
                                .. table.concat(set_to_list(named_families), ", ")
                                .. " (" .. tostring(buckets) .. " buckets)")
                    else
                        local flat = published.FLAT and next(published.FLAT) ~= nil
                        check(buckets > 0 or flat,
                            claim.class .. ": the passage says it still answers every family ("
                                .. tostring(buckets) .. " buckets)")
                    end
                end
            end
        end
    end

    -- The family claims: every key the passage attaches to a family, and every
    -- key the passage excludes from one.
    if passage then
        -- run: the keys since the last qualifier; last_positive: the list the
        -- last positive qualifier covered (a "the same N keys" clause resolves
        -- against it).
        local run, last_positive = {}, {}
        for index, key in ipairs(keys) do
            local prev_end = 0
            if index > 1 then prev_end = keys[index - 1].stop end
            local next_start = #passage + 1
            if keys[index + 1] then next_start = keys[index + 1].start end
            local head = passage:sub(prev_end + 1, key.start - 1)
            local tail = passage:sub(key.stop + 1, next_start - 1)
            local families, every = parse_family_list(tail)
            local negative = head:lower():find("without", 1, true) ~= nil
            local class = key.class
            local published = class and published_neutral(ROOT .. CLASS_FILE[class], class)
            if published then
                if negative then
                    -- "WITHOUT `key` on <families>": the tree must NOT publish the
                    -- key there, and the "the same N keys" clause (when the
                    -- passage states one) must resolve to the list before it.
                    local same = head:lower():match("the same (%a+) keys")
                    if same then
                        local resolved = {}
                        for _, entry in ipairs(last_positive) do
                            if entry.name ~= key.name and entry.class == class then
                                resolved[#resolved + 1] = entry.name
                            end
                        end
                        local number = NUMBER_WORDS[same]
                        check(number == nil or number == #resolved,
                            class .. ": the passage's 'the same " .. same
                                .. " keys' clause names " .. tostring(#resolved) .. " keys")
                        if families then
                            for _, name in ipairs(resolved) do
                                for family in pairs(families) do
                                    local bucket = published[family]
                                    check(bucket ~= nil and bucket[name] == true,
                                        class .. ": the passage's 'the same " .. same
                                            .. " keys' clause publishes '" .. name
                                            .. "' on " .. family)
                                end
                            end
                        end
                    end
                    if families then
                        for family in pairs(families) do
                            local bucket = published[family]
                            check(bucket == nil or bucket[key.name] == nil,
                                class .. ": the passage excludes '" .. key.name
                                    .. "' on " .. family)
                        end
                    end
                    run = {}
                else
                    if families then
                        -- a positive claim covers the run of keys before it (the
                        -- keys of the same class that carry no claim of their own).
                        local covered = {}
                        for _, entry in ipairs(run) do
                            if entry.class == class then covered[#covered + 1] = entry.name end
                        end
                        covered[#covered + 1] = key.name
                        for _, name in ipairs(covered) do
                            if every then
                                for family, bucket in pairs(published) do
                                    check(bucket[name] == true,
                                        class .. ": the passage publishes '" .. name
                                            .. "' on every family (" .. family .. ")")
                                end
                            else
                                for family in pairs(families) do
                                    local bucket = published[family]
                                    check(bucket ~= nil and bucket[name] == true,
                                        class .. ": the passage publishes '" .. name
                                            .. "' on " .. family)
                                end
                            end
                        end
                        last_positive = {}
                        for _, name in ipairs(covered) do
                            last_positive[#last_positive + 1] = { name = name, class = class }
                        end
                        run = {}
                    else
                        run[#run + 1] = { name = key.name, class = class }
                    end
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- The local budget: Lua 5.1's hard ceiling is 200 locals per function prototype
-- ---------------------------------------------------------------------------
-- WHY THIS EXISTS: Lua 5.1 caps one function at 200 local variables ("main
-- function has more than 200 local variables"), so ONE more local in a
-- prototype that already sits at the ceiling is a LOAD FAILURE on every client
-- - not a test failure, and the harness's luac5.1 -p step only catches it when
-- the harness runs. The final publish-gate audit measured the paladin and the
-- warrior AT the ceiling (200, zero headroom) and the shaman one slot below it
-- (199) - bench/final_gate_audit_2026-10-20.md HIGH-3. Their constants now
-- ride the module table (the class modules' own APL_UTILITY / WARRIOR_UTILITY
-- precedent), so the ceiling is far away - and this check keeps it that way:
-- the next lane sees the headroom BEFORE it trips it, not after the client
-- fails to load.
--
-- THE COUNT IS THE COMPILER'S OWN: `luac5.1 -l -l` prints each function
-- prototype's own local count ("0+ params, N slots, 0 upvalues, N locals, ..."),
-- which is the number the compiler itself enforces. It counts the NAMES - a
-- `local a, b` line is two locals - and it includes the locals declared inside a
-- file-scope block (they share the chunk's budget). The ceiling is PER FUNCTION,
-- and the class files register their body as a loader closure (operator order
-- 2026-10-21), so the wrapper chunk carries only the header's locals while the
-- real module count lives in the nested body: the guard therefore takes the
-- MAXIMUM across every prototype in the file, not the first (the wrapper). No
-- source scan can drift from it, and no refactor can change it by accident.
--
-- THE LIMIT IS 190: a file above it is the warning this check exists for, ten
-- slots before the ceiling.
--
-- THE BASELINE IS A RATCHET: practice_ui.lua sits at 199 - at the ceiling -
-- and is not a file this lane may change. A baselined file may not grow past
-- its baseline (the baseline can be tightened, never raised); every other file
-- is held to the 190 limit.

local LOCAL_LIMIT = 190
local LOCAL_BASELINE = {
    -- At the ceiling (199 of 200). Any new file-scope local there must be
    -- balanced by removing one - the module table is the way (the class
    -- modules' own precedent).
    ["practice_ui.lua"] = 199,
}

-- The compiler's own local count for one file: the MAX across every function
-- prototype (the per-function ceiling). The first prototype is the file's main
-- chunk; a loader-wrapped class file keeps its real count in the nested body
-- closure, so returning the first match would measure the wrapper (3 locals)
-- instead of the body. nil when luac cannot read it - never a guess: a file
-- whose count cannot be read FAILS the check below.
local function luac_list_lines(path)
    -- -o: luac writes its bytecode stream to this file. Without -o it defaults to
    -- luac.out in the cwd, which used to dirty the tracked repo-root artifact on
    -- every harness run. The temp file is removed immediately.
    local tmp = os.tmpname()
    local lines = shell_lines('luac5.1 -l -l -o "' .. tmp .. '" "' .. path .. '" 2>/dev/null')
    os.remove(tmp)
    return lines
end
local function compiler_local_count(path)
    local max_n = nil
    for _, line in ipairs(luac_list_lines(path)) do
        local n = line:match("upvalues, (%d+) locals")
        if n then
            n = tonumber(n)
            if max_n == nil or n > max_n then max_n = n end
        end
    end
    return max_n
end

-- Every addon module (the repo root and classes/ - the chunks the client
-- loads). The test files are separate chunks and are not counted here.
local local_budget_files = {}
for name in pairs(dir_entries(ROOT)) do
    if name:match("%.lua$") then
        local_budget_files[#local_budget_files + 1] = name
    end
end
for name in pairs(dir_entries(ROOT .. "classes/")) do
    if name:match("%.lua$") then
        local_budget_files[#local_budget_files + 1] = "classes/" .. name
    end
end
table.sort(local_budget_files)
check(#local_budget_files > 0, "the addon has .lua modules to count against the local ceiling")

local tightest_file, tightest_count = nil, nil
for _, rel in ipairs(local_budget_files) do
    local count = compiler_local_count(ROOT .. rel)
    local limit = LOCAL_BASELINE[rel] or LOCAL_LIMIT
    if count == nil then
        check(false, rel .. ": the file-scope local count could not be read (luac5.1 -l -l)")
    else
        check(count <= limit, rel .. ": " .. tostring(count)
            .. " locals in its densest prototype (limit "
            .. tostring(limit) .. ", headroom " .. tostring(200 - count) .. ")")
        if tightest_count == nil or count > tightest_count then
            tightest_file, tightest_count = rel, count
        end
    end
end
-- PIN: classes/rogue.lua has the loader-wrapper shape (every class file now
-- registers its body in st.class_loaders; operator order 2026-10-21). Its main
-- chunk carries the header's locals while the body closure carries the module's
-- real count, so this proves the guard reads the MAX across prototypes and not
-- the wrapper's first match.
local rogue_main_count, rogue_body_count = nil, nil
for _, line in ipairs(luac_list_lines(ROOT .. "classes/rogue.lua")) do
    local n = line:match("upvalues, (%d+) locals")
    if n then
        n = tonumber(n)
        if rogue_main_count == nil then rogue_main_count = n end
        if rogue_body_count == nil or n > rogue_body_count then rogue_body_count = n end
    end
end
check(rogue_main_count ~= nil and rogue_body_count ~= nil
    and rogue_body_count > rogue_main_count
    and compiler_local_count(ROOT .. "classes/rogue.lua") == rogue_body_count,
    "the local guard measures the class body, not the loader wrapper (main chunk "
        .. tostring(rogue_main_count) .. ", body " .. tostring(rogue_body_count) .. " locals)")
check(tightest_file ~= nil,
    "the tightest addon file is " .. tostring(tightest_file) .. " at "
    .. tostring(tightest_count) .. " locals in its densest prototype (the ceiling is 200)")

print("")
print(string.format("%d checks, %d failures", checks, failures))
if failures > 0 then
    os.exit(1)
end
os.exit(0)

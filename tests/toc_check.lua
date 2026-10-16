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

        -- compat.lua before main.lua (covers that both are listed)
        local compat_index, main_index
        for i, entry in ipairs(entries) do
            if entry == "compat.lua" and compat_index == nil then compat_index = i end
            if entry == "main.lua" and main_index == nil then main_index = i end
        end
        check(compat_index and main_index and compat_index < main_index,
            toc .. ": compat.lua before main.lua")

        -- P9 load order: swing_source.lua needs compat's st.family/st.api and must load
        -- before main.lua (which reads st.swing_source while it loads); weave.lua is pure
        -- and loads before main.lua; class modules load after main.lua.
        local swing_source_index, weave_index, twist_index, shaman_index
        for i, entry in ipairs(entries) do
            if entry == "swing_source.lua" and swing_source_index == nil then swing_source_index = i end
            if entry == "weave.lua" and weave_index == nil then weave_index = i end
            if entry == "twist.lua" and twist_index == nil then twist_index = i end
            if entry == "classes\\shaman.lua" and shaman_index == nil then shaman_index = i end
        end
        check(compat_index and swing_source_index and swing_source_index > compat_index
                and main_index and swing_source_index < main_index,
            toc .. ": compat.lua before swing_source.lua before main.lua")
        check(twist_index and weave_index and main_index
                and twist_index < weave_index and weave_index < main_index,
            toc .. ": twist.lua before weave.lua before main.lua")
        check(shaman_index and main_index and shaman_index > main_index,
            toc .. ": classes\\shaman.lua loads after main.lua")

        -- every addon .lua module on disk is listed
        for _, module_path in ipairs(root_modules) do
            check(seen[module_path] == true, toc .. ": lists " .. module_path)
        end
        for _, module_path in ipairs(class_modules) do
            check(seen[module_path] == true, toc .. ": lists " .. module_path)
        end
    end
end

print("")
print(string.format("%d checks, %d failures", checks, failures))
if failures > 0 then
    os.exit(1)
end
os.exit(0)

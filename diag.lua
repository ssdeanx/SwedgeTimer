--=========================================================================================
-- Diagnostics: one print-only self-report for the owner's test session.
--
-- Every failure mode in this addon is silent: the 5 s init deadline disarms a library with
-- one chat notice, nil-guards render nothing, the non-paladin guides default OFF, and
-- Retail hides swings on purpose - so a broken load and a clean one look identical
-- in-client. This module turns the login moment and /st diag into evidence.
--
-- Hard rules (enforced by tests/diag_state.lua):
--   * PRINT-ONLY. Nothing here writes any state: no frames are created, no SavedVariables
--     are written (the profile tables are only read), no events are registered, no class
--     logic is called, and no library interface is modified.
--   * It NEVER throws. The public body and every probe are pcall-wrapped, every read is
--     nil-safe, and a value that cannot be read renders as "?" instead of erroring.
--   * Output is capped to diag.MAX_LINES lines per report.
--
-- The login report (st.diag.report(self), called once at the end of init_libs) is one
-- line; /st diag adds the verbose lines. Field sources, all read-only:
--   st.family / st.interface_number  compat.lua's client-family detection
--   self.addon_version               main.lua's version (kept in sync with the TOCs)
--   self.swing_engine                the swing engine in use: "vendored-lib" |
--                                    "forever-source" | "inert-standin"
--   self.lrc_ready / lrc_unavailable LibRangeCheck state (the init-deadline fallback)
--   LibStub("LibClassicDurations")   the seal-cooldown library (Era/TBC only)
--   st.ldb.obj / st.ldb.init_attempted  the LibDataBroker feed (ldb.lua)
--   self.<CLASS>.guide               the frozen guide provider contract
--   self.db.profile[<CLASS>]         guide enablement (nextaction_enabled)
--   self.stl_ready / llm_ready / lrc_ready / lrc_unavailable  init readiness flags
--   self.interfaces_are_initialised  set by init_libs once everything is up
--   self.init_deadline_fired         set by the 5 s deadline when it had to rescue init
--   st.practice_ui / st.hud / st.rotation_text / st.designmode  the UI modules
--   C_Secrets                        the secret-value restriction predicates (Mainline)
--=========================================================================================
local _, st = ...

st.diag = st.diag or {}
local diag = st.diag

-- Hard output cap. The verbose report is 4 lines today, so this is headroom for a broken
-- field, never a truncation the owner should see.
diag.MAX_LINES = 6

local PREFIX = "SwedgeTimer diag:"

-- The classes that ship a guide provider. Guide enablement is the per-class
-- nextaction_enabled setting - exactly what nextaction_ui.should_show reads.
local PROVIDER_CLASSES = { "PALADIN", "WARRIOR", "DRUID", "SHAMAN", "HUNTER" }

--=========================================================================================
-- Emission (never throws)
--=========================================================================================
-- diag.sink is the test hook (tests/diag_state.lua captures lines through it); production
-- prints to the chat frame. Both paths are pcall-wrapped: a protected, broken or absent
-- printer must degrade to silence, never to an error.
local function print_line(text)
    local sink = diag.sink
    if type(sink) == "function" then
        if pcall(sink, text) then
            return
        end
    end
    pcall(print, text)
end

--=========================================================================================
-- Nil-safe reads and probes (never throw)
--=========================================================================================
-- One read, pcall-wrapped so even a hostile metatable cannot escape.
local function read(root, key)
    if type(root) ~= "table" then
        return nil
    end
    local ok, value = pcall(function() return root[key] end)
    if ok then
        return value
    end
    return nil
end

-- Scalar rendering: strings/numbers/booleans print, anything else is "unknown".
local function show(value)
    local kind = type(value)
    if kind == "string" or kind == "number" or kind == "boolean" then
        return tostring(value)
    end
    return "?"
end

-- Readiness flags: true/false where set, "?" where the field does not exist yet.
local function flag(value)
    if value == nil then
        return "?"
    end
    if value then
        return "true"
    end
    return "false"
end

-- LibRangeCheck: ready, disabled by the init deadline (fallback), or unknown.
local function lrc_state(self)
    if read(self, "lrc_unavailable") == true then
        return "fallback"
    end
    if read(self, "lrc_ready") == true then
        return "ready"
    end
    return "?"
end

-- LibClassicDurations presence, through LibStub's silent form. Its absence is a
-- legitimate state (the library is Era/TBC-only); a broken or missing LibStub is unknown.
local function lcd_state()
    if type(LibStub) ~= "function" then
        return "?"
    end
    local ok, lib = pcall(LibStub, "LibClassicDurations", true)
    if not ok then
        return "?"
    end
    if lib ~= nil then
        return "present"
    end
    return "absent"
end

-- LibDataBroker object: created, pending (the lazy init has not run yet), absent (the
-- creation attempt failed - e.g. the library is missing), or unknown.
local function ldb_state()
    local l = read(st, "ldb")
    if type(l) ~= "table" then
        return "?"
    end
    if read(l, "obj") ~= nil then
        return "object"
    end
    if read(l, "init_attempted") == true then
        return "absent"
    end
    return "pending"
end

-- The frozen guide provider contract (nextaction_ui.get_provider): a table with gather
-- and evaluate functions. Read, never called.
local function has_guide_provider(self, class)
    local class_module = read(self, class)
    local guide = read(class_module, "guide")
    return type(guide) == "table"
        and type(guide.gather) == "function"
        and type(guide.evaluate) == "function"
end

-- "on"/"off" when a provider exists (nextaction_enabled gates the guide frame; nil counts
-- as on, the same rule nextaction_ui.should_show applies), "none" when the class module
-- has no provider loaded, "?" when the profile cannot be read.
local function guide_state(self, class)
    if not has_guide_provider(self, class) then
        return "none"
    end
    local profile = read(read(self, "db"), "profile")
    local db_class = read(profile, class)
    if type(db_class) ~= "table" then
        return "?"
    end
    if db_class.nextaction_enabled == false then
        return "off"
    end
    return "on"
end

local function provider_count(self)
    local n = 0
    for i = 1, #PROVIDER_CLASSES do
        if has_guide_provider(self, PROVIDER_CLASSES[i]) then
            n = n + 1
        end
    end
    return n
end

--=========================================================================================
-- Line construction
--=========================================================================================
local function guides_text(self)
    local parts = {}
    for i = 1, #PROVIDER_CLASSES do
        parts[#parts + 1] = PROVIDER_CLASSES[i] .. ":" .. guide_state(self, PROVIDER_CLASSES[i])
    end
    return "guides=" .. table.concat(parts, " ")
end

-- The login line: family, interface, version, engine, LibRangeCheck, LibClassicDurations,
-- LibDataBroker and every guide's state. One line, always printed.
local function config_line(self)
    return string.format(
        "%s family=%s iface=%s version=%s engine=%s lrc=%s lcd=%s ldb=%s %s",
        PREFIX,
        show(read(st, "family")),
        show(read(st, "interface_number")),
        show(read(self, "addon_version")),
        show(read(self, "swing_engine")),
        lrc_state(self),
        lcd_state(),
        ldb_state(),
        guides_text(self))
end

-- Verbose line: the init readiness flags and the deadline/init state.
local function flags_line(self)
    return string.format(
        "%s flags stl_ready=%s llm_ready=%s lrc_ready=%s lrc_unavailable=%s deadline=%s init=%s",
        PREFIX,
        flag(read(self, "stl_ready")),
        flag(read(self, "llm_ready")),
        flag(read(self, "lrc_ready")),
        flag(read(self, "lrc_unavailable")),
        read(self, "init_deadline_fired") == true and "fired" or "no",
        read(self, "interfaces_are_initialised") == true and "yes" or "no")
end

-- Verbose line: the UI modules this TOC set loaded and the guide-provider count.
local function loaded_text(module)
    if module ~= nil then
        return "yes"
    end
    return "no"
end

local function modules_line(self)
    return string.format(
        "%s modules practice=%s hud=%s rotation=%s design=%s providers=%d/%d",
        PREFIX,
        loaded_text(read(st, "practice_ui")),
        loaded_text(read(st, "hud")),
        loaded_text(read(st, "rotation_text")),
        loaded_text(read(st, "designmode")),
        provider_count(self),
        #PROVIDER_CLASSES)
end

-- Secret-value restriction predicates (Mainline clients) - the switches that decide
-- whether restricted reads come back as opaque secrets. C_Secrets is absent on classic
-- clients, where the line is just "secrets api=no". Every probe is pcall'd; a missing,
-- throwing or non-boolean probe renders "?" rather than erroring.
local SECRET_PROBES = {
    { "restrictions", "HasSecretRestrictions", {} },
    { "cd", "ShouldCooldownsBeSecret", {} },
    { "aura", "ShouldAurasBeSecret", {} },
    { "power", "ShouldUnitPowerBeSecret", { "player" } },
    { "stats", "ShouldUnitStatsBeSecret", {} },
    { "cast", "ShouldUnitSpellCastingBeSecret", { "player" } },
}

local function secret_probe_flag(c_secrets, name, args)
    local probe = read(c_secrets, name)
    if type(probe) ~= "function" then
        return "?"
    end
    local ok, value = pcall(probe, unpack(args))
    if ok and type(value) == "boolean" then
        return value and "true" or "false"
    end
    return "?"
end

local function secrets_line()
    local c_secrets = rawget(_G, "C_Secrets")
    if type(c_secrets) ~= "table" then
        return PREFIX .. " secrets api=no"
    end
    local parts = { "secrets api=yes" }
    for i = 1, #SECRET_PROBES do
        local probe = SECRET_PROBES[i]
        parts[#parts + 1] = probe[1] .. "="
            .. secret_probe_flag(c_secrets, probe[2], probe[3])
    end
    return PREFIX .. " " .. table.concat(parts, " ")
end

--=========================================================================================
-- Public entry point
--=========================================================================================
-- st.diag.report(self, verbose): print the report. Never throws, never writes. Each line
-- is built under its own pcall, so one unreadable field can only cost its own line.
function diag.report(self, verbose)
    local ok, lines = pcall(function()
        local out = {}
        local built, line = pcall(config_line, self)
        out[#out + 1] = built and line or (PREFIX .. " config unavailable")
        if verbose then
            local flags_ok, flags = pcall(flags_line, self)
            out[#out + 1] = flags_ok and flags or (PREFIX .. " flags unavailable")
            local modules_ok, modules = pcall(modules_line, self)
            out[#out + 1] = modules_ok and modules or (PREFIX .. " modules unavailable")
            local secrets_ok, secrets = pcall(secrets_line)
            out[#out + 1] = secrets_ok and secrets or (PREFIX .. " secrets unavailable")
        end
        return out
    end)
    if not ok or type(lines) ~= "table" then
        print_line(PREFIX .. " report failed (see the Lua error log)")
        return
    end
    local cap = tonumber(diag.MAX_LINES) or 6
    for i = 1, #lines do
        if i > cap then
            break
        end
        print_line(lines[i])
    end
end

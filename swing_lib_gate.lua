--=========================================================================================
-- Swing-library load gate (single-TOC release, 2026-11-07).
--
-- The addon ships ONE SwedgeTimer.toc for every client (operator order 2026-11-07), so
-- the TOC can no longer omit LibClassicSwingTimerAPI on the clients where that library
-- must not run. The library is a classic-line engine:
--   * WoW Forever: main.lua prefers a present library over swing_source, which would
--     replace the native PLAYER_SWING engine with the classic CLEU engine (this client
--     has no classic combat log, so the bars would go dead).
--   * Retail: same, and no classic combat log either.
--   * Cata / Mists: the library's spell tables are only initialised for Classic/BCC/
--     Wrath, so its engine is incomplete there (AGENTS.md "Cross-engine").
--
-- HOW THE GATE WORKS: LibStub:NewLibrary(major, minor) returns nil when an equal-or-
-- higher minor is already registered (Libs/LibStub/LibStub.lua:20-28), and the vendored
-- library's first statement is
--     local lib = LibStub:NewLibrary(MAJOR, MINOR)
--     if not lib then return end
-- so pre-registering a stub at GATE_MINOR turns the whole vendored file into a no-op
-- without touching anything under Libs/ (the vendoring rule).
--
-- The stub exists only for the instant between this file and the library's TOC line:
-- swing_lib_gate_release.lua (the next line after the library) removes it again, so no
-- other addon ever sees a fake LibClassicSwingTimerAPI in the shared LibStub registry.
-- main.lua additionally treats a still-tagged stub as absent (belt and braces).
--=========================================================================================
local _, st = ...

local MAJOR = "LibClassicSwingTimerAPI"
-- Far above the vendored MINOR (32): an upstream minor bump cannot silently re-enable
-- the library on a gated client. Pinned by tests/toc_check.lua.
local GATE_MINOR = 1000000

-- True only on the clients that own a classic combat log and a complete spell table:
-- Classic Era, TBC Anniversary and Wrath. Mirrors compat.lua's family detection (the
-- gate loads before compat, so it reads the same globals directly).
local function classic_line_client()
    local project = rawget(_G, "WOW_PROJECT_ID")
    if project ~= nil then
        return project == rawget(_G, "WOW_PROJECT_CLASSIC")
            or project == rawget(_G, "WOW_PROJECT_BURNING_CRUSADE_CLASSIC")
            or project == rawget(_G, "WOW_PROJECT_WRATH_CLASSIC")
    end
    -- Legacy/private clients without WOW_PROJECT_ID: mirror compat's interface fallback.
    -- 16000+ is WoW Forever (it shares the 1.x major) and is NOT classic-line.
    local get_build_info = rawget(_G, "GetBuildInfo")
    if type(get_build_info) == "function" then
        local ok, _, _, _, toc = pcall(get_build_info)
        local interface = ok and tonumber(toc) or nil
        if interface ~= nil then
            local major = math.floor(interface / 10000)
            -- WoW Forever shares Classic Era's major version (1.60.x -> 16000+) but is
            -- Mainline-code, so it is never classic-line (compat.lua has the same rule).
            if major == 1 and interface >= 16000 then
                return false
            end
            return major == 1 or major == 2 or major == 3
        end
    end
    return false
end

if LibStub ~= nil and not classic_line_client() then
    local ok, stub = pcall(LibStub.NewLibrary, LibStub, MAJOR, GATE_MINOR)
    if ok and stub ~= nil then
        stub.__st_gate_stub = true
    end
end

if st.debug and st.utils and type(st.utils.print_msg) == "function" then
    st.utils.print_msg("-- Parsed swing_lib_gate.lua correctly")
end

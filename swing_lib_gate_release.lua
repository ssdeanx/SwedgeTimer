--=========================================================================================
-- Swing-library gate release (see swing_lib_gate.lua).
--
-- The vendored LibClassicSwingTimerAPI TOC line sits between the gate and this file. On
-- a gated client the library returned at its LibStub guard, so the stub the gate
-- registered is removed here: the shared LibStub registry must not keep a fake
-- LibClassicSwingTimerAPI for the rest of the session (another addon embedding the real
-- library would otherwise receive the stub instead of its own copy).
--
-- On a classic-line client the gate did nothing and the real library registered itself,
-- so there is nothing to release.
--=========================================================================================
local _ = ...

local MAJOR = "LibClassicSwingTimerAPI"

if LibStub ~= nil and type(LibStub.libs) == "table" then
    -- Mutate through locals: luacheck reads a direct `LibStub.libs[..] = nil` as mutating
    -- a non-standard global, and the registry write itself is intentional (see above).
    local libs = LibStub.libs
    local lib = libs[MAJOR]
    if lib ~= nil and lib.__st_gate_stub == true then
        libs[MAJOR] = nil
        local minors = LibStub.minors
        if type(minors) == "table" then
            minors[MAJOR] = nil
        end
    end
end

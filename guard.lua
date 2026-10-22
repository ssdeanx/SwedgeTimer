--=========================================================================================
-- guard.lua: the addon's ONE error-isolation contract (deep audit F10).
--
-- Six modules used to carry their own copy of the same contract: bars.lua, hud.lua,
-- nextaction_ui.lua, practice_ui.lua (twice) and rotationtext.lua. Every copy had its
-- own quarantine constant (25), its own counter bookkeeping and its own wording, and
-- the copies had already drifted: the practice start path printed on every refusal
-- while the other five printed the first failure of a site once.
--
-- This module owns the contract ONCE. What stays at the call site:
--   * the site key - the counter name and the text inside the message;
--   * the wording - each consumer registers its own label ("Bar update", "HUD",
--     "Next action", "Practice", "Rotation text" stay where they belong);
--   * the degraded result (hide / unknown / freeze) - the guard isolates a failure, it
--     never decides what the feature shows instead.
--
-- The contract, unchanged:
--   * every failure is counted (owner.bar_hook_errors.count and .by_site[site]);
--   * the first failure of a site is reported once (never a per-frame chat flood);
--   * a site that keeps throwing is quarantined for the session after
--     st.guard.QUARANTINE_THROWS failures - the quarantine is announced, never silent;
--   * a quarantined site is not called again (no call, no counting, no chat).
--
-- Chat output: the guard announces through the owner's own Print (AceConsole's Print,
-- the addon's established chat path - DEFAULT_CHAT_FRAME:AddMessage). It never reaches
-- the client's raw global print, and a missing Print is not an error: the failure is
-- still counted.
--
-- The counter table is unchanged: { count, by_site, quarantined, first_reported } on the
-- owner, under the name bar_hook_errors (/st diag reads it; main.lua and diag.lua are
-- untouched by this module).
--=========================================================================================
-- The addon name is not needed here (the announcements go through the owner's own
-- Print, the addon's established chat path) - the same shape as twist.lua/weave.lua.
local _, st = ...

st.guard = {}

-- The one quarantine threshold (was six copies: the per-module
-- *_QUARANTINE_THROWS constants). The value is unchanged: 25.
st.guard.QUARANTINE_THROWS = 25

-- The wording per site segment. The segment is the first part of the site key
-- ("hud:cs" -> "hud"), so a consumer registers its label once and every site it owns
-- inherits it. The shared module never hard-codes a module's wording.
local labels = {}

-- Resolved labels per site key. The site keys are stable strings (a zone id, a class
-- name, a fixed name), so the lookup is a hash hit on every tick after the first.
local label_cache = {}

-- Registers the message label for a site segment. The label is the text the site
-- announcements are built from: "<label> error in <site> (isolated): <err>" and
-- "<label> <site> quarantined for this session after repeated errors.".
function st.guard.label(segment, label)
    labels[tostring(segment)] = tostring(label)
    -- A site resolved before this registration cached the fallback label: drop the
    -- cache so the new wording wins from now on.
    label_cache = {}
end

-- The fallback for a site whose segment was never registered. Every consumer registers
-- its own, so this only covers a site added without a label - the failure is still
-- counted and still announced.
local DEFAULT_LABEL = "Update"

local function label_for(site)
    local cached = label_cache[site]
    if cached then
        return cached
    end
    local sep = string.find(site, ":", 1, true)
    local segment = sep and string.sub(site, 1, sep - 1) or site
    local label = labels[segment] or DEFAULT_LABEL
    label_cache[site] = label
    return label
end

-- The counter table every site has always used, on the owner. The name and the fields
-- are read by /st diag and by the suites - they stay exactly as they were.
local function error_table(owner)
    local errors = owner.bar_hook_errors
    if type(errors) ~= "table" then
        errors = { count = 0 }
        owner.bar_hook_errors = errors
    end
    if type(errors.by_site) ~= "table" then
        errors.by_site = {}
    end
    if type(errors.quarantined) ~= "table" then
        errors.quarantined = {}
    end
    if type(errors.first_reported) ~= "table" then
        errors.first_reported = {}
    end
    if type(errors.count) ~= "number" then
        errors.count = 0
    end
    return errors
end

-- The addon's chat path: the owner's own Print. A missing Print is not an error - the
-- failure is still counted, it just has no chat line.
local function announce(owner, message)
    if type(owner) == "table" and type(owner.Print) == "function" then
        owner:Print(message)
    end
end

-- Records a failure for a site: counts it, reports the first failure of the site once,
-- and quarantines the site once it reaches the threshold.
function st.guard.note(owner, site, err)
    if type(owner) ~= "table" then
        return 0
    end
    local key = tostring(site)
    local errors = error_table(owner)
    errors.count = errors.count + 1
    errors.by_site[key] = (errors.by_site[key] or 0) + 1
    if not errors.first_reported[key] then
        errors.first_reported[key] = true
        announce(owner, label_for(key) .. " error in " .. key .. " (isolated): " .. tostring(err))
    end
    if errors.by_site[key] >= st.guard.QUARANTINE_THROWS and not errors.quarantined[key] then
        errors.quarantined[key] = true
        announce(owner, label_for(key) .. " " .. key
            .. " quarantined for this session after repeated errors.")
    end
    return errors.count
end

-- Counts a refusal and prints its reason EVERY time. This is the user-invoked path
-- (the practice start gate): a refusal is not a per-frame loop, so there is no
-- once-per-site throttle here - the counter still lets /st diag show the volume.
function st.guard.refusal(owner, site, message)
    if type(owner) ~= "table" then
        return 0
    end
    local key = tostring(site)
    local errors = error_table(owner)
    errors.count = errors.count + 1
    errors.by_site[key] = (errors.by_site[key] or 0) + 1
    announce(owner, message)
    return errors.count
end

-- Is the site quarantined for this session? A quarantined site is not called again.
function st.guard.quarantined(owner, site)
    if type(owner) ~= "table" then
        return false
    end
    local errors = owner.bar_hook_errors
    if type(errors) ~= "table" then
        return false
    end
    local quarantined = errors.quarantined
    if type(quarantined) ~= "table" then
        return false
    end
    return quarantined[tostring(site)] and true or false
end

-- Runs a call under the contract: pcall, count, report once, quarantine. The results
-- mirror pcall's own shape: (true, ...) on success, (false, err) on a throw and
-- (false) for a quarantined site - the call is skipped there, and nothing is counted.
local function forward(owner, site, ok, ...)
    if not ok then
        st.guard.note(owner, site, ...)
    end
    return ok, ...
end

function st.guard.run(owner, site, fn, ...)
    local key = tostring(site)
    if st.guard.quarantined(owner, key) then
        return false
    end
    return forward(owner, key, pcall(fn, ...))
end

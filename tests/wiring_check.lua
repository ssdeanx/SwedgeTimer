--=========================================================================================
-- Static wiring-parity check for SwedgeTimer.
--
-- WHY THIS EXISTS (the two bugs it is built to catch):
--   BUG 1 (dead feature): ST:UNIT_POWER_FREQUENT existed as a handler in main.lua and its
--     class hook (warrior/druid rage colouring) was covered by PASSING unit tests, but the
--     event was never registered - so the whole rage feature never ran in-game. The
--     offline tests invoke hooks directly, so they structurally cannot see this.
--   BUG 2 (crash): UNIT_SPELLCAST_SUCCEEDED / CURRENT_SPELL_CAST_CHANGED dispatched into
--     class hooks that recolour the bar, with no interfaces_are_initialised guard, so
--     casting within ~5s of /reload indexed a nil anchor_frame.
--   Both are pure wiring defects: every behaviour test passes, the feature is simply
--   unreachable (BUG 1) or reachable too early (BUG 2). Only a check that reads the
--   dispatch graph can see them.
--
-- WHAT IT DOES: reads the addon sources as TEXT (io.open + read, never load/executes them)
-- and asserts five invariants. Every check prints one PASS/FAIL line naming file:line
-- evidence, and the script exits non-zero if any check fails.
--
-- NON-VACUITY: a static scan fails silently when its pattern stops matching - this file
-- once shipped an api-contract counter that matched ZERO references for weeks and printed a
-- happy "0 api.* reference(s)". Every scan therefore asserts a minimum match count (floors
-- drawn from the counts this tree produces today, noted at each call site), and an
-- ALLOWLIST_CLOCK entry whose file no longer reads raw GetTime( is reported stale.
--
--   1. EVENT REGISTRATION PARITY - every self:RegisterEvent / RegisterUnitEvent /
--      RegisterCallback / RegisterChatCommand target in main.lua has a matching
--      `function ST:X(` handler, AND every UPPER_SNAKE `function ST:X(` handler in
--      main.lua is registered by at least one of those. Both directions are reported.
--      (Upper-snake only: lowercase ST: methods are internal helpers, not AceEvent
--      dispatch targets - `ST[event](ST, event, ...)` can only ever reach event-shaped
--      names. OnInitialize and friends are therefore out of scope by construction.)
--   2. CLASS HOOK DISPATCH - every `function ST.<CLASS>.<hook>(` in classes/*.lua is
--      dispatched from another module (a real call site, `.hook(` / `["hook"](` form), or
--      called within its own module as `self.<CLASS>.hook(`. A hook with NO call site
--      anywhere is BUG 1's exact shape and FAILS.
--   3. INIT-GUARD PARITY - every registered main.lua handler that forwards into bar
--      visuals (set_bar_color, on_bar_update, on_bar_active/inactive, the frame getters,
--      or any class hook) must either guard on interfaces_are_initialised in the handler,
--      carry the guard in the class hook it reaches, or be ACCEPTED with a written reason.
--      This is the check that fires when BUG 2's guard is deleted.
--   4. API CONTRACT - every api.<name> / st.api.<name> referenced in the addon modules
--      must be assigned in compat.lua (`api.X =`, `function api.X(` or `api.X.Y =`), and
--      classes/*.lua must not call a bare cross-client WoW global that belongs in compat.
--   5. CLOCK RULE - GetTimePreciseSec( is a hard ban outside compat.lua; GetTime( is
--      banned outside compat.lua except the files listed in ALLOWLIST_CLOCK. GetTime( and
--      GetTimePreciseSec( are NOT also reported by check 4 (comment: check 5 owns them) so
--      one defect never prints twice.
--   6. REVERSE CLASS-HOOK RESOLUTION - the mirror image of check 2: every LITERAL class
--      hook call site (`self.<CLASS>.<hook>(` / `ST.<CLASS>.<hook>(`) in main.lua,
--      bars.lua and classes/*.lua must resolve to a `function ST.<CLASS>.<hook>(`
--      definition in classes/<class>.lua, and every runtime class-dispatch site
--      (`class.<hook>(` / `self[self.player_class].<hook>(`) must name a hook at least
--      one class module defines. A guarded site (`if class.on_x then class.on_x(...)`)
--      is an optional hook: that is legitimate ONLY when it is written down in
--      ALLOWLIST_OPTIONAL with a one-line reason, so a rename of an unguarded call site
--      (or of a guarded one whose entry was not updated) fails while a documented
--      optional hook passes. Allowlist rot is reported exactly like ACCEPTED.
--
-- SEVERITY MODEL - three outcomes, deliberately distinct:
--   ok       invariant holds.
--   FAIL     invariant violated. Exits non-zero.
--   accepted a violation that is KNOWN and ACCEPTED today, listed in ACCEPTED with a
--            written reason. Printed with file:line on every run and counted, but does not
--            fail the run: these are pre-existing defects awaiting the owner's triage, not
--            new breakage. Deleting the ACCEPTED entry promotes the defect back to FAIL,
--            and an entry whose defect no longer reproduces prints as `stale accept`.
--            This keeps the suite green on a known-defective tree WITHOUT hiding anything:
--            nothing is suppressed silently, and accept-list rot is reported.
--
-- Plain Lua 5.1, no WoW client needed: lua5.1 tests/wiring_check.lua
-- The repo root is derived from this script's own location, so any cwd works. Every file
-- is read fresh on each run (no on-disk cache, no cross-run memoisation).
--=========================================================================================

local script_dir = (arg[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
local ROOT = script_dir .. "/.."

--=========================================================================================
-- ALLOWLIST - every deliberate exception, one line of reason each.
-- Keys are "<check>|<file>|<slug>" where the slug is exactly what the check emits, so an
-- entry that stops matching cannot silently keep a defect suppressed: it is reported as
-- `stale accept` and fails the run. Never add an entry to silence a checker bug - fix the
-- checker. Every entry below was verified against the code it describes.
--=========================================================================================

-- Check 3: handlers that forward into bar visuals without an
-- interfaces_are_initialised guard in the handler itself. Slug = the event name lowercased.
local ACCEPTED = {
	-- --- deliberate, no defect
	["3|main.lua|swing_timer_start-no-guard"] =
		"Swing-engine callbacks are registered by register_timer_callbacks(), which "
		.. "init_timers() calls at main.lua:521 - one line AFTER interfaces_are_initialised "
		.. "is set at main.lua:520. The engine therefore cannot deliver a callback before "
		.. "the frames exist.",
	["3|main.lua|swing_timer_stop-no-guard"] =
		"Registered by register_timer_callbacks() after the flag is set (see "
		.. "swing_timer_start-no-guard); the C_Timer body that reaches on_bar_inactive is "
		.. "later still.",
	["3|main.lua|swing_timer_update-no-guard"] =
		"Registered by register_timer_callbacks() after the flag is set (see "
		.. "swing_timer_start-no-guard).",

	-- --- pre-existing compat-contract defect (check 4)
}

-- Check 5: files allowed to read raw GetTime(). Everything added after P9 must use
-- api.get_time(); these entries are legacy code that legitimately lives in the GetTime()
-- domain, or standalone libraries with no access to st.api. Like ACCEPTED, an entry whose
-- file no longer reads raw GetTime( is reported as stale and fails the run: no entry may
-- silently keep allowing nothing.
local ALLOWLIST_CLOCK = {
	["compat.lua"] =
		"The clock's reference domain: GetTimePreciseSec() is converted into it once here. "
		.. "This is the only file allowed to touch either raw clock.",
	["main.lua"] =
		"Legacy pre-P9 code in the GetTime() domain: it stores and compares the swing "
		.. "engine's timestamps (self[hand].start / ends_at), which arrive in that domain.",
	["bars.lua"] =
		"Legacy pre-P9 code in the GetTime() domain: its progress/fill maths compares against "
		.. "the swing engine's timestamps, which are stamped with GetTime() in main.lua.",
	["swing_source.lua"] =
		"The Forever swing engine must hand back timestamps in the same domain main.lua and "
		.. "bars.lua compare in.",
	["LibGlobalCooldown.lua"] =
		"Vendored library loaded outside the addon namespace; it never sees st.api.",
	["LibLatencyMonitor.lua"] =
		"Vendored library loaded outside the addon namespace; it never sees st.api.",
}

-- Check 6: guarded class-hook call sites whose hook no class module defines - the
-- deliberate optional-hook pattern (`if class.on_x then class.on_x(...) end`). Keyed
-- "<file>|<slug>", slug "CLASS.hook" for a literal site and "hook (dynamic)" for a
-- runtime dispatch. Same contract as ACCEPTED: every entry carries a one-line reason,
-- a site that resolves to a real definition needs NO entry, and an entry whose guarded
-- site no longer exists is reported stale and fails the run. There are no entries today
-- (every guarded dispatch in this tree names a hook some class module defines): the
-- table exists so the first genuine optional hook gets a written reason instead of a
-- silent hole.
local ALLOWLIST_OPTIONAL = {
}

-- Check 3: BAR_VISUAL_TRIGGERS is derived from the code, not hardcoded: every method whose
-- body touches a bar frame, plus every class hook found by check 2. Adding a frame-touching
-- method to the ST namespace and naming it below is the only manual step.
local BAR_VISUAL_METHODS = {
	set_bar_color = true,
	on_bar_update = true,
	on_bar_active = true,
	on_bar_inactive = true,
	on_attack_speed_change = true,
	on_gcd_length_change = true,
	on_latency_update = true,
	set_deadzone_width = true,
	set_gcd_marker_positions = true,
	set_gcd_times_before_swing_seconds = true,
	handle_bar_visibility = true,
	set_bar_visibilities = true,
	show_bar = true,
	hide_bar = true,
	-- frame getters: get_visuals_frame reads self[hand].anchor_frame.bar_frame.visuals_frame,
	-- so any direct call is already a pre-init crash.
	get_visuals_frame = true,
	get_bar_frame = true,
	get_anchor_frame = true,
	get_hiding_anchor_frame = true,
}

-- Check 4: bare cross-client globals that classes/*.lua must reach through compat instead.
-- GetTime(/GetTimePreciseSec( are deliberately absent: check 5 owns the clock rule, and a
-- defect must never be reported twice.
local BARE_GLOBALS = {
	{ pattern = "([^%w_.])(UnitPower)%(", name = "UnitPower" },
	{ pattern = "([^%w_.])(UnitPowerMax)%(", name = "UnitPowerMax" },
	{ pattern = "([^%w_.])(UnitAura)%(", name = "UnitAura" },
	{ pattern = "([^%w_.])(UnitCastingInfo)%(", name = "UnitCastingInfo" },
	{ pattern = "([^%w_.])(UnitChannelInfo)%(", name = "UnitChannelInfo" },
	{ pattern = "([^%w_.])(C_Spell)%.", name = "C_Spell" },
	{ pattern = "([^%w_.])(C_UnitAuras)%.", name = "C_UnitAuras" },
}

--=========================================================================================
-- Reporting
--=========================================================================================

local checks, failures, accepted_count, stale_count = 0, 0, 0, 0
local accepted_seen = {}

local function ok(label)
	checks = checks + 1
	print("ok   " .. label)
end

-- report(check_id, file, line, slug, label, reason_if_accepted)
-- label is the invariant sentence; reason_if_accepted is looked up in ACCEPTED by
-- "<check_id>|<file>|<slug>". An ACCEPTED hit is reported but does not fail the run; the
-- entry is recorded so a no-longer-reproducing defect can be reported stale at the end.
local function report(check_id, file, line, slug, label, reason_if_accepted)
	checks = checks + 1
	local evidence = string.format("%s:%d", file, line)
	if reason_if_accepted then
		local key = check_id .. "|" .. file .. "|" .. slug
		if ACCEPTED[key] then
			accepted_seen[key] = true
			accepted_count = accepted_count + 1
			print(string.format("FAIL %s [accepted] %s - %s", evidence, label, ACCEPTED[key]))
			return
		end
	end
	failures = failures + 1
	print(string.format("FAIL %s %s", evidence, label))
end

local function section(title)
	print("")
	print("-- " .. title)
end

-- Non-vacuity guard for the scans below: a check silently passes when its pattern stops
-- matching, so each scan asserts a minimum match count. Floors are drawn from the counts
-- the tree produced when the guard was added (noted at each call site); they only trip
-- when a scan stops seeing what it is supposed to see.
local function require_min(count, minimum, what)
	checks = checks + 1
	if count >= minimum then
		print(string.format("ok   non-vacuity: %s = %d (floor %d)", what, count, minimum))
	else
		failures = failures + 1
		print(string.format(
			"FAIL non-vacuity: %s = %d, below floor %d - the scan matched (almost) nothing, "
			.. "so its results cannot be trusted; fix the scan's pattern", what, count, minimum))
	end
end

--=========================================================================================
-- Filesystem + source reading (text only; nothing is ever loaded or executed)
--=========================================================================================

local function shell_lines(cmd)
	local out = {}
	if not io.popen then return out end
	local pipe = io.popen(cmd)
	if not pipe then return out end
	for line in pipe:lines() do
		out[#out + 1] = line
	end
	pipe:close()
	return out
end

local function sorted_ls(dir, pattern)
	local names = {}
	for _, entry in ipairs(shell_lines('ls -1 "' .. dir .. '" 2>/dev/null')) do
		if entry:match(pattern) then
			names[#names + 1] = entry:match("([^/]+)$") or entry
		end
	end
	table.sort(names)
	return names
end

-- Blanks comments while preserving line count (and column positions), so every pattern
-- match carries a true file:line and a comment can never be mistaken for code. Handles:
-- -- line comments, --[[ ]] / --[=[ ]=] long comments, "..." / '...' strings with escapes,
-- and [[ ]] / [=[ ]=] long strings. This is a scanner, not a parser: it is exact for this
-- codebase's style (which contains no nested long brackets) and never loads the source.
--
-- The long-bracket opener is matched as ^(%[=*)%[ - a literal `[`, then `=`s, then a literal
-- `[` - so a plain table/index bracket such as self.class_hands[self.player_class] is NOT
-- mistaken for one (the looser ^([%[=]*)%[ matches every line starting with `[`).
local function blank_comments(src)
	local _, newlines = src:gsub("\n", "")
	local out = {}
	for i = 1, newlines + 1 do out[i] = "" end

	local i, len = 1, #src
	local line = 1
	local state = "code" -- code | line | long
	local level = 0

	local function put(ch)
		out[line] = out[line] .. ch
	end

	-- Advance to the next line, keeping out dense so ipairs/# stay meaningful.
	local function next_line()
		line = line + 1
		if out[line] == nil then out[line] = "" end
		out[line] = ""
		if state == "line" then state = "code" end
	end

	while i <= len do
		local c = src:sub(i, i)
		if c == "\n" then
			next_line()
			i = i + 1
		elseif state == "line" then
			i = i + 1 -- comment body: dropped
		elseif state == "long" then
			local close = "]" .. string.rep("=", level) .. "]"
			local s = src:find(close, i, true)
			if s then
				-- blank the whole span, keeping the newlines it contains
				local stop = s + #close - 1
				local skipped = src:sub(i, stop)
				out[line] = out[line] .. string.rep(" ", #skipped)
				local _, nl = skipped:gsub("\n", "")
				for _ = 1, nl do next_line() end
				i = stop + 1
				state = "code"
			else
				put(c)
				i = i + 1
			end
		else -- state == "code"
			local _, _, opener = src:find("^(%[=*)%[", i)
			if c == "[" and opener then
				level = #opener - 1
				out[line] = out[line] .. opener .. "["
				i = i + #opener + 1
				state = "long"
			elseif c == "-" and src:sub(i + 1, i + 1) == "-" then
				local _, _, opener2 = src:find("^(%[=*)%[", i + 2)
				if opener2 then
					level = #opener2 - 1
					out[line] = out[line] .. "  " .. opener2 .. "["
					i = i + 2 + #opener2 + 1
					state = "long"
				else
					state = "line"
					i = i + 2
				end
			elseif c == '"' or c == "'" then
				local quote = c
				put(c)
				i = i + 1
				while i <= len do
					local ch = src:sub(i, i)
					if ch == "\\" then
						put(ch)
						put(src:sub(i + 1, i + 1))
						i = i + 2
					elseif ch == quote then
						put(ch)
						i = i + 1
						break
					elseif ch == "\n" then
						-- unterminated string: do not run past the line
						next_line()
						i = i + 1
						break
					else
						put(ch)
						i = i + 1
					end
				end
			else
				put(c)
				i = i + 1
			end
		end
	end
	return out
end

local SRC = {}
local function load_src(path)
	local f = io.open(ROOT .. "/" .. path, "r")
	if not f then
		SRC[path] = nil
		return false
	end
	local text = f:read("*a")
	f:close()
	SRC[path] = { raw = blank_comments(text), code = {} }
	for ln, l in ipairs(SRC[path].raw) do
		SRC[path].code[ln] = l
	end
	return true
end

local function code_of(path) return SRC[path].code end

-- Extract a function body span by keyword depth. Counts `function`, `if`, `for`, `while`
-- and `repeat` as openers and `end`/`until` as closers; the `do` of a `for`/`while` header is
-- not counted (its opener already is) and `elseif` is one token, so it never double-counts.
-- main.lua contains no bare `do` blocks, which is what makes this exact for this file.
local function function_span(path, start_line)
	local code = code_of(path)
	local depth = 1
	local idx = start_line
	local seen_signature = false
	while idx <= #code and depth > 0 do
		local line = code[idx]
		local pos = 1
		while pos <= #line do
			local s, e, word = line:find("([%a_][%w_]*)", pos)
			if not s then break end
			if not seen_signature then
				-- skip the signature's own `function` token
				seen_signature = true
			else
				if word == "function" or word == "if" or word == "for"
					or word == "while" or word == "repeat" then
					depth = depth + 1
				elseif word == "end" or word == "until" then
					depth = depth - 1
					if depth == 0 then
						return start_line, idx
					end
				end
			end
			pos = e + 1
		end
		idx = idx + 1
	end
	return start_line, #code
end

local function span_text(path, first, last)
	local parts = {}
	for ln = first, last do parts[#parts + 1] = code_of(path)[ln] end
	return table.concat(parts, "\n")
end

--=========================================================================================
-- 0. Inventory - what is actually on disk right now
--=========================================================================================

local ROOT_LUA = sorted_ls(ROOT, "%.lua$")
local CLASS_LUA = {}
for _, name in ipairs(sorted_ls(ROOT .. "/classes", "%.lua$")) do
	CLASS_LUA[#CLASS_LUA + 1] = "classes/" .. name
end

section("0. inventory")
ok(string.format("found %d root module(s) and %d class module(s) to check",
	#ROOT_LUA, #CLASS_LUA))

for _, path in ipairs(ROOT_LUA) do
	if load_src(path) then
		ok(path .. ": readable")
	else
		failures = failures + 1
		print("FAIL " .. path .. ": readable")
	end
end
for _, path in ipairs(CLASS_LUA) do
	if load_src(path) then
		ok(path .. ": readable")
	else
		failures = failures + 1
		print("FAIL " .. path .. ": readable")
	end
end

-- The modules this script reasons about must exist, or every other check is vacuous.
for _, path in ipairs({ "main.lua", "bars.lua", "compat.lua" }) do
	if SRC[path] then
		ok("required module present: " .. path)
	else
		failures = failures + 1
		print("FAIL required module present: " .. path)
	end
end

--=========================================================================================
-- 1. EVENT REGISTRATION PARITY (main.lua)
--=========================================================================================

section("1. event registration parity (main.lua)")

local handlers = {}   -- name -> definition line
for ln, line in ipairs(code_of("main.lua")) do
	for name in line:gmatch("function ST:([%w_]+)%s*%(") do
		if handlers[name] == nil then
			handlers[name] = ln
		end
	end
end

-- registration kinds, keyed by the name the dispatcher will look up
local registrations = {}  -- name -> { kind, line }
local anon_callbacks = {}

local function add_registration(name, kind, ln)
	if name == nil or name == "" then return end
	local list = registrations[name]
	if list == nil then
		registrations[name] = { { kind = kind, line = ln } }
	else
		list[#list + 1] = { kind = kind, line = ln }
	end
end

for ln, line in ipairs(code_of("main.lua")) do
	for name in line:gmatch("RegisterEvent%s*%(%s*\"([%w_]+)\"") do
		add_registration(name, "RegisterEvent", ln)
	end
	for name in line:gmatch("RegisterUnitEvent%s*%(%s*\"([%w_]+)\"") do
		add_registration(name, "RegisterUnitEvent", ln)
	end
	for _, target in line:gmatch("RegisterChatCommand%s*%(%s*\"[^\"]+\"%s*,%s*\"([%w_]+)\"") do
		add_registration(target, "RegisterChatCommand", ln)
	end
	-- LibStub callbacks: LibX.RegisterCallback(self, <name>, <handler-or-function>).
	-- The tail capture must be `(.*)$`, not `(.)$`: a single-char class cannot backtrack,
	-- so `(.)$` made the whole pattern unmatchable and silently recorded ZERO lib-callback
	-- registrations - which then made every SWING_TIMER_*/GCD_*/LATENCY_CHANGED handler
	-- look unregistered. The name is a string literal or a `LIB.NAME` constant.
	for _, arg, tail in line:gmatch(
		"([%a_][%w_]*)%.RegisterCallback%s*%(%s*self%s*,%s*([^,]+),%s*(.*)$") do
		local name = arg:match("^\"([%w_]+)\"") or arg:match("^[%a_][%w_]*%.([%a_][%w_]*)$")
		if tail:find("function%s*%(") then
			-- inline handler: nothing to dispatch to
			anon_callbacks[#anon_callbacks + 1] = { name = name, line = ln }
		elseif name then
			add_registration(name, "RegisterCallback", ln)
		end
	end
end

-- Direction A: every registration resolves to a handler.
for name, list in pairs(registrations) do
	table.sort(list, function(a, b) return a.line < b.line end)
	local evidence = string.format("main.lua:%d", list[1].line)
	local kinds = {}
	for _, r in ipairs(list) do kinds[#kinds + 1] = r.kind end
	if handlers[name] then
		ok(string.format("%s registers %q -> function ST:%s( at main.lua:%d [%s]",
			evidence, name, name, handlers[name], table.concat(kinds, ",")))
	else
		failures = failures + 1
		print(string.format("FAIL %s %s registers %q but no function ST:%s( exists",
			evidence, list[1].kind, name, name))
	end
end

-- Direction B: every event-shaped handler is actually registered somewhere.
for name, ln in pairs(handlers) do
	if name:match("^[A-Z][A-Z0-9_]*$") then
		if registrations[name] then
			ok(string.format("main.lua:%d handler ST:%s( is registered", ln, name))
		else
			failures = failures + 1
			print(string.format(
				"FAIL main.lua:%d handler ST:%s( is NEVER registered - the event can never fire "
				.. "(dead feature)", ln, name))
		end
	end
end

for _, cb in ipairs(anon_callbacks) do
	ok(string.format("main.lua:%d lib callback %s handled inline (no ST:%s handler required)",
		cb.line, cb.name or "?", cb.name or "?"))
end

--=========================================================================================
-- 2. CLASS HOOK DISPATCH (classes/*.lua)
--=========================================================================================

section("2. class hook dispatch (classes/*.lua)")

local class_hooks = {}   -- { class=, hook=, file=, line= }
for _, path in ipairs(CLASS_LUA) do
	local code = code_of(path)
	for ln, line in ipairs(code) do
		for class, hook in line:gmatch("function ST%.([A-Z][A-Z0-9_]*)%.([%a_][%w_]*)%s*%(") do
			class_hooks[#class_hooks + 1] =
				{ class = class, hook = hook, file = path, line = ln }
		end
	end
end

-- Non-vacuity floor 10 (current tree: 77 hook definitions): if the scan stops finding the
-- `function ST.<CLASS>.<hook>(` spelling, every "has a call site" verdict below vanishes.
require_min(#class_hooks, 10, "ST.<CLASS>.<hook>( definition(s) found")

-- Modules a class hook may legitimately be dispatched from: the addon core, the widget
-- layer, the other class modules, and the UI modules that own the paladin hooks. A call
-- site only counts when it can be attributed to a specific module, so this is an ordered
-- list plus a membership set.
local DISPATCH_SOURCES = {}
local DISPATCH_LIST = {}
for _, path in ipairs(ROOT_LUA) do
	DISPATCH_SOURCES[path] = true
	DISPATCH_LIST[#DISPATCH_LIST + 1] = path
end
for _, path in ipairs(CLASS_LUA) do
	if not DISPATCH_SOURCES[path] then
		DISPATCH_SOURCES[path] = true
		DISPATCH_LIST[#DISPATCH_LIST + 1] = path
	end
end

-- hook name -> set of classes defining it. Needed because a generic dispatcher
-- (`self[self.player_class].hook(`) reaches whichever class is active, so a dynamic call
-- site is proof of dispatch for every class that defines that hook name.
local HOOK_CLASSES = {}
for _, h in ipairs(class_hooks) do
	HOOK_CLASSES[h.hook] = HOOK_CLASSES[h.hook] or {}
	HOOK_CLASSES[h.hook][h.class] = true
end
local ALL_HOOK_NAMES = {}
for _, h in ipairs(class_hooks) do ALL_HOOK_NAMES[h.hook] = true end

-- Words on a blanked line, each tagged with the text preceding it. The gap is what tells
-- a dotted receiver chain (`self.PALADIN.`) apart from a bare call (`hook(`).
local function words_of(text)
	local out, pos = {}, 1
	while pos <= #text do
		local s, e, word = text:find("([%a_][%w_]*)", pos)
		if not s then break end
		out[#out + 1] = { word = word, from = s, to = e, gap = text:sub(pos, s - 1) }
		pos = e + 1
	end
	return out
end

-- Leftmost word of the dotted expression ending at word `idx` (inclusive).
local function chain_left(words, idx)
	local base = idx
	while base > 1 and words[base].gap:match("^[%s%.]*$") do base = base - 1 end
	return base
end

-- `function ST.<CLASS>.<hook>(` is the only definition spelling used in classes/*.lua, so
-- a site is a definition exactly when the receiver chain it belongs to is that header.
-- Any other `ST.CLASS.hook(` is a real call - nextaction_ui.lua dispatches that way - and a
-- bare `function hook(` is caught by the same test applied to the preceding word.
local function is_definition(words, idx)
	-- Words before the second one cannot start the `function ST.<CLASS>.<hook>(` header,
	-- and chain_left() cannot walk below index 1; without this guard a scanner that
	-- probes a call-shaped word at the start of a line indexes words[0].
	if idx < 2 then return false end
	local base = chain_left(words, idx - 1)
	for k = base, idx - 1 do
		if words[k].word == "ST" and words[k - 1] and words[k - 1].word == "function" then
			return true
		end
	end
	return words[idx - 1] ~= nil and words[idx - 1].word == "function"
end

-- Every invocation of `hook` in [first, last] of `path`, classified by how the name is
-- reached so a dispatch can be attributed to one specific class hook:
--   kind = "qualified"  `self.PALADIN.hook(` / `ST.PALADIN.hook(`   qualifier = the class
--   kind = "keyed"      `["hook"](`                              qualifier = the literal key
--   kind = "dynamic"    `class.hook(` / `self[c].hook(`           qualifier = nil: the
--                       receiver is a runtime expression, so the target class is whatever
--                       the player currently is
--   kind = "bare"       `hook(` on its own name - a local/upvalue alias, only trusted
--                       inside the module that defines it
--   kind = "method"     `self:hook(` - a call into the ST namespace, NOT into ST.<CLASS>
local function call_sites(path, hook, first, last)
	local code = code_of(path)
	local out = {}
	for ln = (first or 1), (last or #code) do
		local line = code[ln]
		if line then
			local words = words_of(line)
			for i = 1, #words do
				local w = words[i]
				if w.word == hook then
					local after = line:sub(w.to + 1)
					local pad = after:match("^%s*") or ""
					if after:sub(#pad + 1, #pad + 1) == "(" and not is_definition(words, i) then
						local site
						local before = line:sub(1, w.from - 1):gsub("%s+$", "")
						if before:match(":%s*$") then
							-- `self:hook(` is a method call into the ST namespace, not a
							-- dispatch into ST.<CLASS> - it is not a class-hook call site.
							site = { kind = "method" }
						elseif before:match("%.$") then
							-- drop the field separator: what is left is the receiver
							local recv = before:sub(1, -2):gsub("%s+$", "")
							local keyed = recv:match("[\"']([^\"']*)[\"']%]$")
							local field = words[i - 1] and words[i - 1].word or nil
							-- A class token is UPPER_SNAKE and must have a receiver in front
							-- of it, so `self.PALADIN.hook(` qualifies but `table.hook(`
							-- and `self[c].hook(` stay dynamic.
							if keyed then
								site = { kind = "keyed", qualifier = keyed }
							elseif recv:match("%]$") then
								site = { kind = "dynamic" }
							elseif field and field:match("^[A-Z][A-Z0-9_]*$")
								and chain_left(words, i - 1) < i - 1 then
								site = { kind = "qualified", qualifier = field }
							else
								site = { kind = "dynamic" }
							end
						elseif before:match("[\"']$") and before:match("[%[.]$") then
							site = { kind = "keyed",
								qualifier = before:match("[\"']([^\"']*)[\"']$") }
						else
							site = { kind = "bare" }
						end
						if site then
							site.line = ln
							out[#out + 1] = site
						end
					end
				end
			end
		end
	end
	return out
end

-- Does `site` prove that ST.<class>.<hook> is dispatched?
local function dispatches(site, class, hook, own_file, path)
	if site.kind == "qualified" then return site.qualifier == class end
	if site.kind == "keyed" then return site.qualifier == hook end
	-- The generic dispatcher reaches whichever class is active, so it is proof for every
	-- class that defines a hook of this name.
	if site.kind == "dynamic" then return true end
	-- `self:hook(` is an ST-namespace method call, never a class dispatch.
	if site.kind == "method" then return false end
	-- A bare name is only trusted inside the module that defines it, where the identifier
	-- unambiguously means that hook.
	return path == own_file
end

table.sort(class_hooks, function(a, b)
	if a.file ~= b.file then return a.file < b.file end
	return a.line < b.line
end)

for _, h in ipairs(class_hooks) do
	local evidence = string.format("%s:%d", h.file, h.line)
	local label = string.format("ST.%s.%s( has a call site", h.class, h.hook)

	local found, found_file, found_line, how
	for _, path in ipairs(DISPATCH_LIST) do
		for _, site in ipairs(call_sites(path, h.hook)) do
			if dispatches(site, h.class, h.hook, h.file, path) then
				found, found_file, found_line = true, path, site.line
				how = site.kind
				break
			end
		end
		if found then break end
	end

	if found then
		ok(string.format("%s %s (%s:%d, %s)", evidence, label, found_file, found_line,
			how == "bare" and "module-internal bare call" or (how .. " dispatch")))
	else
		report("2", h.file, h.line, h.hook .. "-unwired",
			string.format("ST.%s.%s( is defined but NEVER called from any module - dead hook",
				h.class, h.hook),
			true)
	end
end

--=========================================================================================
-- 3. INIT-GUARD PARITY (main.lua handlers that reach bar visuals)
--=========================================================================================

section("3. init-guard parity (main.lua -> bar visuals)")

local GUARD = "interfaces_are_initialised"

-- Class-hook guard lookup, built from the class modules and keyed "<CLASS>.<hook>" so two
-- classes that share a hook name (PALADIN.glow_start / WARRIOR.glow_start) cannot collide.
local hook_bodies = {}
for _, path in ipairs(CLASS_LUA) do
	local code = code_of(path)
	for i = 1, #code do
		local class, hook = code[i]:match("function ST%.([A-Z][A-Z0-9_]*)%.([%a_][%w_]*)%s*%(")
		if class then
			local first, last = function_span(path, i)
			hook_bodies[class .. "." .. hook] =
				{ text = span_text(path, first, last), file = path, line = first,
					first = first, last = last }
		end
	end
end

-- Which class hooks does a body reach? Uses the same call-site classifier as check 2, so a
-- `self.PALADIN.hook(` call names one hook and a `class.hook(` dispatch names every class
-- that defines a hook of that name.
local function reached_hooks(path, first, last)
	local reached = {}
	for hook in pairs(ALL_HOOK_NAMES) do
		for _, site in ipairs(call_sites(path, hook, first, last)) do
			if site.kind == "qualified" and hook_bodies[site.qualifier .. "." .. hook] then
				reached[site.qualifier .. "." .. hook] = true
			elseif site.kind == "keyed" or site.kind == "dynamic" then
				for class in pairs(HOOK_CLASSES[hook] or {}) do
					reached[class .. "." .. hook] = true
				end
			end
			-- "method" (`self:hook(`) is an ST-namespace call, and a bare mention only
			-- counts inside the defining module, so neither dispatches into ST.<CLASS>.
		end
	end
	local list = {}
	for k in pairs(reached) do list[#list + 1] = k end
	table.sort(list)
	return list
end

local function touches_bar_visuals(path, first, last)
	local body = span_text(path, first, last)
	local triggers = {}
	for name in pairs(BAR_VISUAL_METHODS) do
		if body:find("[:%.]" .. name .. "%s*%(") then triggers[#triggers + 1] = name end
	end
	local hooks = reached_hooks(path, first, last)
	for _, h in ipairs(hooks) do triggers[#triggers + 1] = "class hook " .. h end
	table.sort(triggers)
	return triggers, hooks
end

-- Does a class hook actually reach a bar visual? A hook that only assigns state (the
-- shaman weave catalogue, the paladin twist counters) cannot crash a frame however
-- unguarded it is, so counting it as an unguarded bar-visual path is a false positive.
-- Resolved through the hook's own body and, one level at a time, the hooks it reaches.
local hook_touches_cache = {}
local function hook_touches(qualified, depth)
	local cached = hook_touches_cache[qualified]
	if cached ~= nil then return cached end
	local hb = hook_bodies[qualified]
	if not hb or (depth or 0) > 6 then return false end
	local result = false
	for name in pairs(BAR_VISUAL_METHODS) do
		if hb.text:find("[:%.]" .. name .. "%s*%(") then result = true break end
	end
	if not result then
		for _, h in ipairs(reached_hooks(hb.file, hb.first, hb.last)) do
			if hook_touches(h, (depth or 0) + 1) then result = true break end
		end
	end
	hook_touches_cache[qualified] = result
	return result
end

-- main.lua's `class_on_*` helpers are the dispatchers into the class modules (the seven
-- spellcast handlers forward into class_on_spellcast_event, UNIT_AURA into
-- class_on_aura_change, CURRENT_SPELL_CAST_CHANGED into class_on_current_spell_cast_changed).
-- A registered handler that forwards into one is not itself where the guard has to live, so
-- those helpers are analysed in their own right: the verdict lands on the code that touches
-- the bars instead of being reported seven times over on thin forwarders. The family is a
-- closed set of three, which is why the expansion is explicit rather than "every helper" -
-- following every helper would drag init_libs (the code that CREATES the frames) in as an
-- unguarded bar-visual path.
local HELPERS = {}
for ln, line in ipairs(code_of("main.lua")) do
	for name in line:gmatch("function ST:([%a_][%w_]*)%s*%(") do
		if HELPERS[name] == nil then HELPERS[name] = ln end
	end
end

-- Which class_on_* dispatchers does this body call? (`self:class_on_x(` reads as kind
-- "method", a bare `class_on_x(` as kind "bare"; both are forwards.)
local function forwarders(path, first, last)
	local out = {}
	for name, ln in pairs(HELPERS) do
		if name:match("^class_on_") then
			for _, site in ipairs(call_sites(path, name, first, last)) do
				if site.kind == "method" or site.kind == "bare" then
					out[#out + 1] = { name = name, line = ln }
					break
				end
			end
		end
	end
	table.sort(out, function(a, b) return a.line < b.line end)
	return out
end

-- Registered handlers only: an unreferenced function is not a live dispatch path. Plus the
-- class_on_* dispatchers, which are live dispatch paths in their own right. Each entry
-- records where the code is (`def`) separately from where it was registered (`reg`):
-- function_span needs the definition, and only the definition is the place a defect lives.
local scope = {}
for name, list in pairs(registrations) do
	if handlers[name] then
		scope[name] = { reg = list[1].line, def = handlers[name] }
	end
end
for name, ln in pairs(HELPERS) do
	if name:match("^class_on_") then scope[name] = { reg = ln, def = ln } end
end

local scoped_names = {}
for name in pairs(scope) do scoped_names[#scoped_names + 1] = name end
table.sort(scoped_names)

-- Who calls each class_on_* dispatcher? A forwarder whose every caller guards
-- interfaces_are_initialised before forwarding cannot run before the frames exist, so the
-- guard is credited upstream. ST:CURRENT_SPELL_CAST_CHANGED (main.lua:797) and ST:UNIT_AURA
-- (main.lua:855) both do exactly that, which is what keeps their class hooks safe.
local FWD_CALLERS = {}
for _, name in ipairs(scoped_names) do
	local def = scope[name].def
	local first, last = function_span("main.lua", def)
	for _, f in ipairs(forwarders("main.lua", first, last)) do
		FWD_CALLERS[f.name] = FWD_CALLERS[f.name] or {}
		FWD_CALLERS[f.name][name] = def
	end
end

-- Does every caller of every dispatcher this function forwards into guard the flag?
local function callers_all_guarded(fwd)
	if #fwd == 0 then return false end
	for _, f in ipairs(fwd) do
		local callers = FWD_CALLERS[f.name] or {}
		local seen = 0
		for _, def in pairs(callers) do
			seen = seen + 1
			local first, last = function_span("main.lua", def)
			if not span_text("main.lua", first, last):find(GUARD, 1, true) then return false end
		end
		if seen == 0 then return false end
	end
	return true
end

local guard_checked = 0
for _, name in ipairs(scoped_names) do
	local line_no = scope[name].def
	local first, last = function_span("main.lua", line_no)
	local body = span_text("main.lua", first, last)
	local triggers, hooks = touches_bar_visuals("main.lua", first, last)
	local fwd = forwarders("main.lua", first, last)
	if #triggers > 0 then
		guard_checked = guard_checked + 1
		local evidence = string.format("main.lua:%d", line_no)
		local what = string.format("ST:%s( -> %s", name, table.concat(triggers, ", "))
		if body:find(GUARD, 1, true) then
			ok(string.format("%s %s: guarded in handler", evidence, what))
		else
			-- the guard may legitimately live in the class hook that receives the dispatch
			local unguarded_hooks = {}
			local relevant = 0
			for _, h in ipairs(hooks) do
				local hb = hook_bodies[h]
				if hb and hook_touches(h) then
					relevant = relevant + 1
					if not hb.text:find(GUARD, 1, true) then
						unguarded_hooks[#unguarded_hooks + 1] =
							string.format("%s (%s:%d)", h, hb.file, hb.line)
					end
				end
			end
			-- The guard may live upstream: either in a dispatcher this function forwards
			-- into, or - when this function IS a class_on_* dispatcher - in every caller
			-- of it, which is the case ST:UNIT_AURA and ST:CURRENT_SPELL_CAST_CHANGED
			-- rely on to gate theirs.
			local upstream_fwd = fwd
			if #upstream_fwd == 0 and name:match("^class_on_") then
				upstream_fwd = { { name = name, line = line_no } }
			end
			local upstream = callers_all_guarded(upstream_fwd)
			if #unguarded_hooks == 0 and #hooks > 0 and not upstream then
				local how = (relevant == #hooks)
					and "guarded in the class hook"
					or "reached class hooks touch no bar visual"
				ok(string.format("%s %s: %s (%s)", evidence, what, how,
					table.concat(hooks, ", ")))
			elseif upstream then
				local where = {}
				for _, f in ipairs(upstream_fwd) do
					where[#where + 1] = string.format("ST:%s(", f.name)
				end
				ok(string.format("%s %s: guarded upstream - every caller of %s checks %s",
					evidence, what, table.concat(where, ", "), GUARD))
			else
				local extra = ""
				if #unguarded_hooks > 0 then
					extra = string.format("; unguarded hooks: %s",
						table.concat(unguarded_hooks, ", "))
				end
				report("3", "main.lua", line_no, name:lower() .. "-no-guard",
					string.format("%s reaches bar visuals with no %s guard%s",
						what, GUARD, extra),
					true)
			end
		end
	elseif #fwd > 0 then
		-- A thin forwarder: name where the dispatch actually continues, so this is never
		-- mistaken for a leaf that needs no guard.
		local where = {}
		for _, f in ipairs(fwd) do
			where[#where + 1] = string.format("ST:%s( (main.lua:%d)", f.name, f.line)
		end
		ok(string.format("main.lua:%d ST:%s( forwards to %s - analysed there",
			line_no, name, table.concat(where, ", ")))
	end
end

-- Non-vacuity floor 5 (current tree: 22 handlers reach bar visuals): a regression in the
-- bar-visual classifier would otherwise leave this guard verifying nothing.
require_min(guard_checked, 5, "registered handler(s) classified as reaching bar visuals")
ok(string.format("%d registered handler(s) reach bar visuals; all carry a guard or an ACCEPTED reason",
	guard_checked))

--=========================================================================================
-- 4. API CONTRACT
--=========================================================================================

section("4. api contract (references -> compat.lua)")

local compat_code = code_of("compat.lua")
local api_defined = {}
for _, line in ipairs(compat_code) do
	for name in line:gmatch("api%.([%a_][%w_]*)%s*=") do
		api_defined[name] = true
	end
	for name in line:gmatch("function api%.([%a_][%w_]*)%s*%(") do
		api_defined[name] = true
	end
end

local api_checked = 0

-- A reference is `api.Name` either bare or qualified (`st.api.Name`, `self.api.Name`):
-- require a non-word boundary before "api." (or the start of the line) so only real
-- references count - the previous single-pattern form matched nothing in either style
-- and silently reported "0 api.* reference(s)".
local function api_refs(line)
	local refs = {}
	-- Prefix a space so every reference has a boundary character: one pattern then catches
	-- both the line-start (`api.X`) and the qualified (`st.api.X`, `self.api.X`) forms.
	-- `myapi.Nope` stays unmatched (the character before `api.` is a word character).
	for name in (" " .. line):gmatch("[^%w_]api%.([%a_][%w_]*)") do
		refs[#refs + 1] = name
	end
	return refs
end

for _, path in ipairs(ROOT_LUA) do
	if path ~= "compat.lua" then
		for ln, line in ipairs(code_of(path)) do
			for _, name in ipairs(api_refs(line)) do
				if api_defined[name] then
					api_checked = api_checked + 1
				else
					failures = failures + 1
					print(string.format(
						"FAIL %s:%d references api.%s but compat.lua never assigns it "
						.. "(contract violation)", path, ln, name))
				end
			end
		end
	end
end
for _, path in ipairs(CLASS_LUA) do
	for ln, line in ipairs(code_of(path)) do
		for _, name in ipairs(api_refs(line)) do
			if api_defined[name] then
				api_checked = api_checked + 1
			else
				failures = failures + 1
				print(string.format(
					"FAIL %s:%d references api.%s but compat.lua never assigns it "
					.. "(contract violation)", path, ln, name))
			end
		end
	end
end
-- Non-vacuity floor 20 (current tree: 153 resolving references): this check is the one
-- that once matched zero references and printed "0 api.* reference(s)" for weeks.
require_min(api_checked, 20, "api.* reference(s) resolving to a compat.lua assignment")

-- Bare cross-client globals in classes/*.lua: must go through compat.
for _, path in ipairs(CLASS_LUA) do
	for ln, line in ipairs(code_of(path)) do
		for _, g in ipairs(BARE_GLOBALS) do
			if line:find(g.pattern) then
				local slug = g.name:lower() .. "-bare"
				report("4", path, ln, slug,
					string.format("bare %s in class module - must go through api.%s (compat.lua)",
						g.name, g.name),
					slug == "unitpower-bare" or slug == "unitpowermax-bare")
			end
		end
	end
end

--=========================================================================================
-- 5. CLOCK RULE
--=========================================================================================

section("5. clock rule (GetTime / GetTimePreciseSec)")

local precise_hits, gettime_hits = 0, 0
local clock_allowlisted_hits, clock_allowlist_seen = 0, {}
local clock_files = {}
for _, path in ipairs(ROOT_LUA) do clock_files[#clock_files + 1] = path end
for _, path in ipairs(CLASS_LUA) do clock_files[#clock_files + 1] = path end

-- The ban matches the NAME, not just a call: compat.lua captures the function parenless
-- (`local precise = GetTimePreciseSec`), and a parenless alias elsewhere leaks raw precise
-- time just as badly as a call would - the old `GetTimePreciseSec%s*%(` form could not see
-- that leak at all. This scan and the compat anchor below share the name pattern, so a
-- regression of one is caught by the other.
for _, path in ipairs(clock_files) do
	if path ~= "compat.lua" then
		for ln, line in ipairs(code_of(path)) do
			if line:find("GetTimePreciseSec") then
				precise_hits = precise_hits + 1
				failures = failures + 1
				print(string.format(
					"FAIL %s:%d references GetTimePreciseSec - raw precise time must never "
					.. "leave compat.lua; use api.get_time()", path, ln))
			end
		end
	end
end
ok(string.format("GetTimePreciseSec is confined to compat.lua (%d stray use(s))", precise_hits))

-- Non-vacuity floor 1 (current tree: 1 reference): compat.lua is where the allowlist
-- expects the precise clock to be converted into the GetTime() domain, so a scan that
-- cannot find it there is blind. The hit also marks compat.lua's ALLOWLIST_CLOCK entry
-- as seen (it is the one file the GetTime loop below never visits).
local precise_in_compat = 0
local compat_touches_clock = false
for _, line in ipairs(compat_code) do
	if line:find("GetTimePreciseSec") then precise_in_compat = precise_in_compat + 1 end
	if line:find("GetTimePreciseSec") or line:find("GetTime%s*%(") then
		compat_touches_clock = true
	end
end
require_min(precise_in_compat, 1, "GetTimePreciseSec reference(s) in compat.lua")
if compat_touches_clock then clock_allowlist_seen["compat.lua"] = true end

for _, path in ipairs(clock_files) do
	if path ~= "compat.lua" then
		local allowed = ALLOWLIST_CLOCK[path]
		for ln, line in ipairs(code_of(path)) do
			if line:find("GetTime%s*%(") and not line:find("GetTimePreciseSec") then
				gettime_hits = gettime_hits + 1
				if allowed then
					clock_allowlisted_hits = clock_allowlisted_hits + 1
					clock_allowlist_seen[path] = true
					ok(string.format("%s:%d GetTime( allowed - %s", path, ln, allowed))
				else
					-- slugs keep each known defect individually tracked
					local slug = "raw-gettime"
					if path:match("paladin") then
						slug = (ln < 700) and "twist-band-clock" or "twist-feedback-clock"
					end
					report("5", path, ln, slug,
						"GetTime( outside compat.lua - post-P9 code must use api.get_time()",
						true)
				end
			end
		end
	end
end
ok(string.format("GetTime( checked outside compat.lua: %d hit(s)", gettime_hits))

-- Non-vacuity / accounting: every counted GetTime( hit must land in an allowlisted file
-- (a hit elsewhere is a defect reported above; a mismatch here means the counting no
-- longer matches the allowlist). Current tree: 11 hits, all in 5 allowlisted files. A
-- fully blind GetTime( pattern reports 0 hits here but still trips the ALLOWLIST_CLOCK
-- staleness check in the summary, so it cannot pass silently either.
checks = checks + 1
if gettime_hits == clock_allowlisted_hits then
	print(string.format("ok   non-vacuity: all %d GetTime( hit(s) land in allowlisted files",
		gettime_hits))
else
	failures = failures + 1
	print(string.format(
		"FAIL non-vacuity: GetTime( scan counted %d hit(s) but only %d in allowlisted "
		.. "files - counting and allowlist disagree (stray uses are reported per-hit above)",
		gettime_hits, clock_allowlisted_hits))
end

--=========================================================================================
-- 6. REVERSE CLASS-HOOK CALL-SITE RESOLUTION
--=========================================================================================

section("6. reverse class-hook call-site resolution (main.lua, bars.lua, classes/*.lua)")

-- Definition lookup from check 2 plus the per-class hook sets, so a literal site can be
-- resolved to one class and a dynamic site to the set of classes that define the hook.
local hook_def = {}
local hook_class_list = {}
for _, h in ipairs(class_hooks) do
	hook_def[h.class .. "." .. h.hook] = h
	hook_class_list[h.hook] = hook_class_list[h.hook] or {}
	hook_class_list[h.hook][h.class] = true
end

-- The definition file a literal ST.<CLASS>.hook must live in: classes/<class>.lua.
local function expected_file(class)
	return "classes/" .. class:lower() .. ".lua"
end

-- A guard is the `if <recv>.<hook> then` test immediately in front of (or around) a
-- call: the same hook name appears in an if-condition within the three lines above the
-- call. This is deliberately textual - the guard is a syntactic contract, and both
-- shapes in this tree (`if class and class.on_x then` and
-- `if self[self.player_class].on_x then`) match it.
local function is_guarded(path, ln, hook)
	local code = code_of(path)
	local first = ln - 3
	if first < 1 then first = 1 end
	for i = first, ln do
		local line = code[i]
		if line and line:find("if") and line:find(hook .. "%s+then") then
			return i
		end
	end
	return nil
end

-- Every class-hook call site in one file, classified:
--   kind = "literal"  `self.PALADIN.hook(` / `ST.PALADIN.hook(`   class = PALADIN
--   kind = "dynamic"  `class.hook(` / `self[self.player_class].hook(` - the receiver is
--                     the class dispatch expression, so the site proves dispatch for
--                     whichever class is active
local function reverse_sites(path)
	local code = code_of(path)
	local out = {}
	for ln = 1, #code do
		local line = code[ln]
		local words = words_of(line)
		for i = 1, #words do
			local w = words[i]
			local after = line:sub(w.to + 1)
			local pad = after:match("^%s*") or ""
			if after:sub(#pad + 1, #pad + 1) == "(" and not is_definition(words, i) then
				local before = line:sub(1, w.from - 1)
				local dot_to_hook = w.gap:match("^%s*%.%s*$") ~= nil
				local cls_w = words[i - 1]
				if dot_to_hook and cls_w and cls_w.word:match("^[A-Z][A-Z0-9_]*$")
					and cls_w.gap:match("^%s*%.%s*$") then
					-- literal: `self.<CLASS>.hook(` / `ST.<CLASS>.hook(`
					local base = words[i - 2]
					if base and (base.word == "self" or base.word == "ST")
						and base.gap:match("^%s*%.%s*$") == nil then
						out[#out + 1] = { kind = "literal", class = cls_w.word,
							hook = w.word, line = ln }
					end
				elseif dot_to_hook and cls_w and cls_w.word == "class" then
					-- dynamic: `class.hook(` - the local dispatch variable
					out[#out + 1] = { kind = "dynamic", receiver = "class",
						hook = w.word, line = ln }
				elseif before:match("%]%s*%.%s*$")
					and before:find("self[self.player_class]", 1, true) then
					-- dynamic: `self[self.player_class].hook(`
					out[#out + 1] = { kind = "dynamic", receiver = "indexed",
						hook = w.word, line = ln }
				end
			end
		end
	end
	return out
end

local REVERSE_FILES = { "main.lua", "bars.lua" }
for _, path in ipairs(CLASS_LUA) do REVERSE_FILES[#REVERSE_FILES + 1] = path end

local reverse_sites_found, literal_sites, dynamic_sites = {}, 0, 0
for _, path in ipairs(REVERSE_FILES) do
	for _, site in ipairs(reverse_sites(path)) do
		site.file = path
		reverse_sites_found[#reverse_sites_found + 1] = site
		if site.kind == "literal" then
			literal_sites = literal_sites + 1
		else
			dynamic_sites = dynamic_sites + 1
		end
	end
end
table.sort(reverse_sites_found, function(a, b)
	if a.file ~= b.file then return a.file < b.file end
	return a.line < b.line
end)

-- Non-vacuity floors 20 / 6 (current tree: 55 literal, 12 dynamic call sites): a scan
-- that stops seeing the call-site spellings reports every verdict below as vacuously
-- fine, so it must be impossible for this check to match nothing.
require_min(literal_sites, 20, "literal self.<CLASS>.<hook>( / ST.<CLASS>.<hook>( call site(s)")
require_min(dynamic_sites, 6, "dynamic class-dispatch call site(s)")

local optional_seen = {}
local optional_hits = 0
for _, site in ipairs(reverse_sites_found) do
	local evidence = string.format("%s:%d", site.file, site.line)
	local slug = site.kind == "literal"
		and (site.class .. "." .. site.hook) or (site.hook .. " (dynamic)")
	local key = site.file .. "|" .. slug
	local guard_line = is_guarded(site.file, site.line, site.hook)

	if site.kind == "literal" then
		local def = hook_def[site.class .. "." .. site.hook]
		if def then
			if def.file == expected_file(site.class) then
				ok(string.format("%s self.%s.%s( resolves to %s:%d", evidence,
					site.class, site.hook, def.file, def.line))
			else
				failures = failures + 1
				print(string.format(
					"FAIL %s self.%s.%s( resolves to %s:%d, not %s - a class hook must be "
					.. "defined in its own class module",
					evidence, site.class, site.hook, def.file, def.line,
					expected_file(site.class)))
			end
		elseif guard_line then
			local reason = ALLOWLIST_OPTIONAL[key]
			if reason then
				optional_seen[key] = true
				optional_hits = optional_hits + 1
				print(string.format(
					"ok   %s self.%s.%s( has no definition - optional hook, guarded at %s:%d - %s",
					evidence, site.class, site.hook, site.file, guard_line, reason))
			else
				failures = failures + 1
				print(string.format(
					"FAIL %s self.%s.%s( is guarded (optional) but undefined and NOT in "
					.. "ALLOWLIST_OPTIONAL - add an entry with a one-line reason, or fix the "
					.. "call: %s", evidence, site.class, site.hook, key))
			end
		else
			failures = failures + 1
			print(string.format(
				"FAIL %s self.%s.%s( has no `function ST.%s.%s(` definition in %s - "
				.. "renamed hook, or a call into nothing", evidence, site.class, site.hook,
				site.class, site.hook, expected_file(site.class)))
		end
	else
		local classes = hook_class_list[site.hook]
		local recv = site.receiver == "indexed" and "self[self.player_class]" or "class"
		if classes then
			local names = {}
			for class in pairs(classes) do names[#names + 1] = class end
			table.sort(names)
			ok(string.format("%s %s.%s( resolves to class module(s) %s", evidence,
				recv, site.hook, table.concat(names, ", ")))
		elseif guard_line then
			local reason = ALLOWLIST_OPTIONAL[key]
			if reason then
				optional_seen[key] = true
				optional_hits = optional_hits + 1
				print(string.format(
					"ok   %s %s.%s( has no definition - optional hook, guarded at %s:%d - %s",
					evidence, recv, site.hook, site.file, guard_line, reason))
			else
				failures = failures + 1
				print(string.format(
					"FAIL %s %s.%s( is guarded (optional) but no class module defines it "
					.. "and it is NOT in ALLOWLIST_OPTIONAL - add an entry with a one-line "
					.. "reason, or fix the dispatch: %s", evidence, recv, site.hook, key))
			end
		else
			failures = failures + 1
			print(string.format(
				"FAIL %s %s.%s( dispatches a hook no class module defines - renamed hook, "
				.. "or a dispatch into nothing", evidence, recv, site.hook))
		end
	end
end

ok(string.format("%d literal + %d dynamic call site(s) checked, %d allowlisted optional",
	literal_sites, dynamic_sites, optional_hits))

--=========================================================================================
-- Summary
--=========================================================================================

section("summary")

local stale = {}
for key in pairs(ACCEPTED) do
	if not accepted_seen[key] then stale[#stale + 1] = key end
end
table.sort(stale)
for _, key in ipairs(stale) do
	stale_count = stale_count + 1
	print("FAIL stale ACCEPTED entry (defect no longer present, delete it): " .. key)
end

-- ALLOWLIST_CLOCK rot, reported exactly like ACCEPTED: an allowlisted file that no longer
-- reads raw GetTime( (or whose hits the scan stopped seeing) means the entry allows nothing
-- and must be deleted.
local stale_clock = {}
for key in pairs(ALLOWLIST_CLOCK) do
	if not clock_allowlist_seen[key] then stale_clock[#stale_clock + 1] = key end
end
table.sort(stale_clock)
for _, key in ipairs(stale_clock) do
	stale_count = stale_count + 1
	print("FAIL stale ALLOWLIST_CLOCK entry (file no longer reads raw GetTime, delete it): "
		.. key)
end

-- ALLOWLIST_OPTIONAL rot: an entry whose guarded call site resolved or vanished would
-- otherwise keep allowing nothing.
local stale_optional = {}
for key in pairs(ALLOWLIST_OPTIONAL) do
	if not optional_seen[key] then stale_optional[#stale_optional + 1] = key end
end
table.sort(stale_optional)
for _, key in ipairs(stale_optional) do
	stale_count = stale_count + 1
	print("FAIL stale ALLOWLIST_OPTIONAL entry (the guarded optional call site no longer "
		.. "exists, delete it): " .. key)
end

print(string.format(
	"%d checks, %d failures, %d accepted known defect(s), %d stale accept(s)",
	checks, failures, accepted_count, stale_count))

if failures > 0 or stale_count > 0 then
	os.exit(1)
end
os.exit(0)

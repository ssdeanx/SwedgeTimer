-- luacheck config for the addon. Run from the repo root: luacheck .
std = "lua51"           -- the addon (and its test scripts) target the Lua 5.1 WoW client
max_line_length = false -- option tables and spell data legitimately have very long lines

-- Vendored Ace3/libs and the archived docs/swedge addons are not ours to lint.
exclude_files = { "Libs/**", "docs/**" }

ignore = {
    "113", -- accessing undefined variable: WoW API globals (GetTime, UnitAura, LibStub, ...)
    "212", -- unused argument: event handlers and library callbacks must keep their signatures
}

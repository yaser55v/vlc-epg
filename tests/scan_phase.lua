-- Simulates VLC's extension scan phase.
-- VLC loads each extension in a stripped-down Lua environment and calls
-- descriptor(). Standard globals such as ipairs, pairs or table are NOT
-- available there, so top-level code must only build literals and define
-- functions. This script runs the file in an empty environment to catch that.
--
-- Usage: lua5.1 tests/scan_phase.lua vlc_epg.lua

local path = arg[1] or "vlc_epg.lua"
local chunk = assert(loadfile(path))
local env = {}
setfenv(chunk, env)
chunk()

assert(type(env.descriptor) == "function", "descriptor() is not defined")
local d = env.descriptor()
assert(type(d) == "table" and d.title, "descriptor() must return a table with a title")
print("scan phase OK: " .. tostring(d.title) .. " " .. tostring(d.version))

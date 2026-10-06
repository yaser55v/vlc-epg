--[[
  VLC EPG
  Loads an M3U playlist into VLC's own playlist and fills its columns with
  XMLTV program info:
    Description = running program and the upcoming ones (you choose how many)
    Genre       = category of the running program
    Album       = synopsis of the running program
    Author      = channel group
  To see them: right-click the playlist column header and enable the columns.

  Install: copy this file to VLC's lua/extensions folder, restart VLC,
  then open it from the View menu.
    Windows: %APPDATA%\vlc\lua\extensions
    Linux:   ~/.local/share/vlc/lua/extensions
    macOS:   ~/Library/Application Support/org.videolan.vlc/lua/extensions

  License: MIT
]]

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------

local CFG_NAME      = "vlc_epg.cfg"
local CACHE_NAME    = "vlc_epg_cache.txt"
local EPG_TTL       = 6 * 3600     -- seconds before the cached guide is refreshed
local WINDOW_BEHIND = 3600         -- keep programs that ended less than 1h ago
local WINDOW_AHEAD  = 36 * 3600    -- keep programs starting within 36h
local OSD_DURATION  = 7000000      -- microseconds
local MAX_PROGRAMS  = 10           -- hard cap of programs per channel in "hours" mode
local SEPARATOR      = "  ||  "     -- between programs in the Description column
local GENRE_FROM_CATEGORY = true   -- Genre column = category of the running program
local ALBUM_FROM_SYNOPSIS = true   -- Album column = synopsis of the running program
local OSD_SYNOPSIS_CHARS  = 160    -- synopsis length shown in the on-screen message

-- Choices offered in the "Show in Description" menu.
local DISPLAY_OPTIONS = {
  { id = 1, label = "2 programs", mode = "count", n = 2 },
  { id = 2, label = "3 programs", mode = "count", n = 3 },
  { id = 3, label = "5 programs", mode = "count", n = 5 },
  { id = 4, label = "Next 2 hours", mode = "hours", n = 2 },
  { id = 5, label = "Next 4 hours", mode = "hours", n = 4 },
  { id = 6, label = "Next 8 hours", mode = "hours", n = 8 },
  { id = 7, label = "Next 12 hours", mode = "hours", n = 12 },
}
local DEFAULT_DISPLAY = 2
local DISPLAY_BY_ID = {
  [1] = DISPLAY_OPTIONS[1],
  [2] = DISPLAY_OPTIONS[2],
  [3] = DISPLAY_OPTIONS[3],
  [4] = DISPLAY_OPTIONS[4],
  [5] = DISPLAY_OPTIONS[5],
  [6] = DISPLAY_OPTIONS[6],
  [7] = DISPLAY_OPTIONS[7],
}
local BOLD_CURRENT  = true         -- fake bold for the running program (Unicode bold letters)

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local state = {
  m3u = "",
  epg = "",
  header_epg = nil,
  channels = {},
  groups = {},
  by_url = {},
  progs = {},
  name_map = {},
  osd = nil,
  guide_note = "",
  display = DEFAULT_DISPLAY,
}

local ui = {}


---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

local function trim(s)
  return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function data_path(name)
  return vlc.config.userdatadir() .. "/" .. name
end

local function utf8_char(cp)
  if cp > 1114111 then return "?" end
  if cp < 128 then
    return string.char(cp)
  elseif cp < 2048 then
    return string.char(192 + math.floor(cp / 64), 128 + cp % 64)
  elseif cp < 65536 then
    return string.char(224 + math.floor(cp / 4096),
                       128 + math.floor(cp / 64) % 64,
                       128 + cp % 64)
  end
  return string.char(240 + math.floor(cp / 262144),
                     128 + math.floor(cp / 4096) % 64,
                     128 + math.floor(cp / 64) % 64,
                     128 + cp % 64)
end

local ENTITIES = { amp = "&", lt = "<", gt = ">", quot = '"', apos = "'", nbsp = " " }

local function decode_once(s)
  s = s:gsub("&#[xX](%x+);", function(h) return utf8_char(tonumber(h, 16)) end)
  s = s:gsub("&#(%d+);", function(d) return utf8_char(tonumber(d)) end)
  s = s:gsub("&(%a+);", function(n) return ENTITIES[n] or ("&" .. n .. ";") end)
  return s
end

-- Some guides escape twice (for example "&amp;#039;"), so decode until the
-- text stops changing (at most 3 passes).
local function decode_text(s)
  if not s then return "" end
  local cdata = s:match("^%s*<!%[CDATA%[(.-)%]%]>%s*$")
  if cdata then return cdata end
  for _ = 1, 3 do
    local decoded = decode_once(s)
    if decoded == s then break end
    s = decoded
  end
  return s
end

local QUALITY = { hd = true, uhd = true, fhd = true, shd = true, sd = true,
                  ["4k"] = true, ["8k"] = true, hevc = true }

local function is_quality(tok)
  return QUALITY[tok] or tok:match("^%d+[pi]$") ~= nil
end

local function tokens_of(str)
  local t = {}
  for tok in str:gmatch("[%w\128-\255]+") do t[#t + 1] = tok end
  return t
end

-- Builds a comparison key from a channel name.
-- Always removes [tags] and quality words (HD, 1080p, 4K ...).
-- strip_all_parens = true also removes other (parenthesised) text such as
-- "(Turkiye)"; that loose key is only used when it is unambiguous.
local function normalize_with(name, strip_all_parens)
  local s = tostring(name or ""):lower()
  s = s:gsub("%b[]", " ")
  s = s:gsub("%b()", function(group)
    local inner = group:sub(2, -2)
    if strip_all_parens then return " " end
    local toks = tokens_of(inner)
    if #toks == 0 then return " " end
    for _, tok in ipairs(toks) do
      if not is_quality(tok) then return " " .. inner .. " " end
    end
    return " "
  end)
  local out = {}
  for _, tok in ipairs(tokens_of(s)) do
    if not is_quality(tok) then out[#out + 1] = tok end
  end
  return table.concat(out)
end

local function normalize(name) return normalize_with(name, false) end
local function normalize_loose(name) return normalize_with(name, true) end

-- Canonical channel id: "ATV.tr@SD" and "ATV.HD.tr" both become "atv.tr".
local ID_NOISE = { hd = true, sd = true, uhd = true, fhd = true, ["4k"] = true }

local function canon_id(id)
  local s = tostring(id or ""):lower()
  s = s:gsub("@.*$", "")
  local out = {}
  for tok in s:gmatch("[^%.]+") do
    if not ID_NOISE[tok] then out[#out + 1] = tok end
  end
  return table.concat(out, ".")
end

local function get_attr(attrs, name)
  return attrs:match(name .. '%s*=%s*"([^"]*)"')
      or attrs:match(name .. "%s*=%s*'([^']*)'")
end

local function expand_home(path)
  if path:sub(1, 2) == "~/" then
    local home = os.getenv("HOME")
    if home then return home .. path:sub(2) end
  end
  return path
end

local function wrap_file(f)
  return {
    read = function(_, n) return f:read(n) end,
    readline = function() return f:read("*l") end,
    close = function() f:close() end,
  }
end

-- Returns a stream object (read / readline) or nil plus a reason.
local function open_stream(src)
  src = expand_home(src)
  if src:match("^%a[%w+.-]*://") then
    local st = vlc.stream(src)
    if st then return st end
    return nil, "VLC could not open " .. src
  end
  local f, err = io.open(src, "rb")
  if f then return wrap_file(f) end
  local st = vlc.stream(vlc.strings.make_uri(src))
  if st then return st end
  return nil, tostring(err or ("cannot open " .. src))
end

local shell_fetch -- defined below

local function set_status(text)
  if ui.status then
    ui.status:set_text(text)
    if ui.dialog then ui.dialog:update() end
  end
end

---------------------------------------------------------------------------
-- Time handling (XMLTV timestamps -> UTC epoch, independent of local TZ)
---------------------------------------------------------------------------

local function days_from_civil(y, m, d)
  if m <= 2 then y = y - 1 end
  local era = math.floor(y / 400)
  local yoe = y - era * 400
  local mp = (m + 9) % 12
  local doy = math.floor((153 * mp + 2) / 5) + d - 1
  local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
  return era * 146097 + doe - 719468
end

local function parse_xmltv_time(s)
  if not s then return nil end
  local y, mo, d, h, mi, se =
    s:match("^%s*(%d%d%d%d)(%d%d)(%d%d)(%d%d)(%d%d)(%d%d)")
  if not y then return nil end
  local t = days_from_civil(tonumber(y), tonumber(mo), tonumber(d)) * 86400
          + tonumber(h) * 3600 + tonumber(mi) * 60 + tonumber(se)
  local sign, oh, om = s:match("([%+%-])(%d%d)(%d%d)%s*$")
  if sign then
    local off = tonumber(oh) * 3600 + tonumber(om) * 60
    if sign == "+" then t = t - off else t = t + off end
  end
  return t
end

local function fmt_time(t)
  return os.date("%H:%M", t)
end

---------------------------------------------------------------------------
-- Configuration
---------------------------------------------------------------------------

local function load_config()
  local f = io.open(data_path(CFG_NAME), "r")
  if not f then return end
  for line in f:lines() do
    local k, v = line:match("^([%w_]+)=(.*)$")
    if k == "m3u" then state.m3u = trim(v) end
    if k == "epg" then state.epg = trim(v) end
    if k == "display" then
      local id = tonumber(v)
      if id and DISPLAY_BY_ID[id] then state.display = id end
    end
  end
  f:close()
end

local function save_config()
  local f = io.open(data_path(CFG_NAME), "w")
  if not f then return false end
  f:write("m3u=", state.m3u, "\n")
  f:write("epg=", state.epg, "\n")
  f:write("display=", state.display, "\n")
  f:close()
  return true
end

---------------------------------------------------------------------------
-- M3U parsing
---------------------------------------------------------------------------

local function parse_m3u_stream(s)
  local channels, seen, groups = {}, {}, {}
  local by_url = {}
  local header_epg = nil
  local pending = nil
  local info = { lines = 0, first = "" }

  while true do
    local line = s:readline()
    if not line then break end
    line = trim(line)
    info.lines = info.lines + 1
    if line ~= "" then
      if info.first == "" then info.first = line:sub(1, 60) end
      if line:sub(1, 7) == "#EXTM3U" then
        local u = get_attr(line, "url%-tvg")
               or get_attr(line, "x%-tvg%-url")
               or get_attr(line, "tvg%-url")
        if u and u ~= "" then header_epg = trim(u:match("^[^,]+")) end
      elseif line:sub(1, 8) == "#EXTINF:" then
        local info = line:sub(9)
        local after = info:match('^.*"()') or 1
        local comma = info:find(",", after, true)
        local name = comma and trim(info:sub(comma + 1)) or ""
        local tvg_name = get_attr(info, "tvg%-name") or ""
        if name == "" then name = tvg_name end
        pending = {
          name = decode_text(name),
          tvg_id = trim(get_attr(info, "tvg%-id") or ""),
          group = trim(get_attr(info, "group%-title") or ""),
        }
      elseif line:sub(1, 8) == "#EXTGRP:" then
        if pending and pending.group == "" then
          pending.group = trim(line:sub(9))
        end
      elseif line:sub(1, 1) ~= "#" then
        if not pending and line:match("^%a[%w+.-]*://") then
          -- plain URL list without #EXTINF: derive a name from the URL
          local base = line:gsub("[?#].*$", ""):match("([^/]+)/*$") or line
          pending = { name = base, tvg_id = "", group = "" }
        end
        if pending then
          pending.url = line
          if pending.name == "" then pending.name = line end
          if pending.group == "" then pending.group = "Other" end
          pending.norm = normalize(pending.name)
          pending.loose = normalize_loose(pending.name)
          channels[#channels + 1] = pending
          by_url[line] = pending
          if not seen[pending.group] then
            seen[pending.group] = true
            groups[#groups + 1] = pending.group
          end
          pending = nil
        end
      end
    end
  end

  -- A loose key shared by channels with different strict names (for example
  -- "BBC One (London)" and "BBC One (Scotland)") is too ambiguous to use.
  local loose_sets, loose_count = {}, {}
  for _, ch in ipairs(channels) do
    local set = loose_sets[ch.loose]
    if not set then set = {}; loose_sets[ch.loose] = set; loose_count[ch.loose] = 0 end
    if not set[ch.norm] then set[ch.norm] = true; loose_count[ch.loose] = loose_count[ch.loose] + 1 end
  end
  for _, ch in ipairs(channels) do
    ch.loose_ambiguous = loose_count[ch.loose] > 1
  end

  table.sort(groups, function(a, b) return a:lower() < b:lower() end)
  return channels, groups, by_url, header_epg, info
end

local function parse_m3u(src)
  local s, serr = open_stream(src)
  local channels, groups, by_url, header_epg, info
  if s then channels, groups, by_url, header_epg, info = parse_m3u_stream(s) end

  -- Some HTTPS servers return nothing to VLC's stream API; retry with curl.
  local empty = (not s) or (info and info.lines == 0)
  if empty and src:match("^https?://") then
    local path = shell_fetch(src)
    if path then
      local s2 = open_stream(path)
      if s2 then channels, groups, by_url, header_epg, info = parse_m3u_stream(s2) end
      os.remove(path)
    end
  end

  if not channels then
    return nil, "Cannot open playlist: " .. tostring(serr or src)
  end
  return channels, groups, by_url, header_epg, info
end

---------------------------------------------------------------------------
-- XMLTV parsing (streaming, only keeps what the playlist needs)
---------------------------------------------------------------------------

local function build_wanted()
  local wanted, keys = {}, {}
  for _, ch in ipairs(state.channels) do
    if ch.tvg_id ~= "" then
      wanted[ch.tvg_id] = true
      keys["i:" .. canon_id(ch.tvg_id)] = true
    end
    if ch.norm ~= "" then keys["n:" .. ch.norm] = true end
    if ch.loose ~= "" and not ch.loose_ambiguous then keys["l:" .. ch.loose] = true end
  end
  return wanted, keys
end

local function same_schedule(a, b)
  for i = 1, 5 do
    local x, y = a[i], b[i]
    if not x and not y then return true end
    if not x or not y then return false end
    if x.start ~= y.start or x.stop ~= y.stop or x.title ~= y.title then return false end
  end
  return true
end

local function clean_field(s, limit)
  s = decode_text(s or "")
  s = s:gsub("[%c]+", " "):gsub("%s+", " ")
  s = trim(s)
  if limit and #s > limit then s = s:sub(1, limit) .. "..." end
  return s
end

local function parse_epg_stream(s)
  local wanted, keys = build_wanted()
  local progs, name_map, cands = {}, {}, {}

  -- Remember which guide channel(s) a key points to. A key that points to
  -- several guide channels is resolved after parsing.
  local function register(key, id)
    if not keys[key] then return end
    wanted[id] = true
    local list = cands[key]
    if not list then
      cands[key] = { id }
      name_map[key] = id
      return
    end
    for _, known in ipairs(list) do
      if known == id then return end
    end
    list[#list + 1] = id
  end
  local now = os.time()
  local lo, hi = now - WINDOW_BEHIND, now + WINDOW_AHEAD

  local buf = ""
  local bytes, chunks, count = 0, 0, 0
  local first = true

  while true do
    local chunk = s:read(65536)
    if not chunk or #chunk == 0 then break end

    if first then
      first = false
      if chunk:byte(1) == 0x1f and chunk:byte(2) == 0x8b then
        return nil, nil, "gzip"
      end
    end

    bytes = bytes + #chunk
    chunks = chunks + 1
    buf = buf .. chunk

    local pos = 1
    local need_more = false
    while not need_more do
      local s0, e0, tag = buf:find("<(%a+)", pos)
      if not s0 then
        buf = buf:sub(-16)
        pos = 1
        need_more = true
      elseif tag ~= "channel" and tag ~= "programme" then
        pos = e0 + 1
      else
        local gt = buf:find(">", e0, true)
        local ce, cf = buf:find("</" .. tag .. ">", e0, true)
        if not gt or not ce then
          buf = buf:sub(s0)
          pos = 1
          need_more = true
        else
          local attrs = buf:sub(e0 + 1, gt - 1)
          local body = buf:sub(gt + 1, ce - 1)
          pos = cf + 1

          if tag == "channel" then
            local id = get_attr(attrs, "id")
            if id then
              register("i:" .. canon_id(id), id)
              for dn in body:gmatch("<display%-name[^>]*>(.-)</display%-name>") do
                local text = decode_text(dn)
                register("n:" .. normalize(text), id)
                register("l:" .. normalize_loose(text), id)
              end
            end
          else
            local ch = get_attr(attrs, "channel")
            if ch and wanted[ch] then
              local st = parse_xmltv_time(get_attr(attrs, "start"))
              local en = parse_xmltv_time(get_attr(attrs, "stop"))
              if st and en and en > lo and st < hi then
                local title = body:match("<title[^>]*>(.-)</title>")
                local desc = body:match("<desc[^>]*>(.-)</desc>")
                local category = body:match("<category[^>]*>(.-)</category>")
                local list = progs[ch]
                if not list then list = {}; progs[ch] = list end
                list[#list + 1] = {
                  start = st,
                  stop = en,
                  title = clean_field(title, 200),
                  desc = clean_field(desc, 400),
                  cat = clean_field(category, 60),
                }
                count = count + 1
              end
            end
          end
        end
      end
    end

    if chunks % 8 == 0 then
      set_status(string.format("Reading guide... %.1f MB, %d programs kept",
                               bytes / 1048576, count))
    end
  end

  for _, list in pairs(progs) do
    table.sort(list, function(a, b) return a.start < b.start end)
  end

  -- Resolve keys that matched several guide channels. Guide channels that are
  -- really the same (for example SD and HD copies) have the same schedule and
  -- are accepted. Different schedules mean the match is ambiguous: no match.
  for key, list in pairs(cands) do
    if #list > 1 then
      local with_data = {}
      for _, id in ipairs(list) do
        if progs[id] and #progs[id] > 0 then with_data[#with_data + 1] = id end
      end
      local ok = true
      for i = 2, #with_data do
        if not same_schedule(progs[with_data[1]], progs[with_data[i]]) then
          ok = false
          break
        end
      end
      if ok and with_data[1] then name_map[key] = with_data[1] else name_map[key] = nil end
    end
  end
  return progs, name_map
end

local function shell_quote(str)
  return "'" .. (str:gsub("'", "'\\''")) .. "'"
end

local function is_readable(path)
  local f = io.open(path, "rb")
  if not f then return false end
  local first = f:read(1)
  f:close()
  return first ~= nil
end

local function is_gzip_file(path)
  local f = io.open(path, "rb")
  if not f then return false end
  local b = f:read(2)
  f:close()
  return b ~= nil and #b == 2 and b:byte(1) == 0x1f and b:byte(2) == 0x8b
end

-- Fallback for sources VLC cannot stream directly (gzip, some HTTPS servers).
-- Uses curl and gzip, which ship with macOS and most Linux systems.
shell_fetch = function(src)
  if not (os and os.execute) then
    return nil, "Shell commands are not available in this VLC"
  end
  local tmp = data_path("vlc_epg_download.tmp")
  local out = data_path("vlc_epg_download.xml")
  os.remove(tmp)
  os.remove(out)

  if src:match("^https?://") then
    os.execute("curl -fsSL --max-time 180 -o " .. shell_quote(tmp) .. " " .. shell_quote(src))
  else
    os.execute("cp " .. shell_quote(src) .. " " .. shell_quote(tmp))
  end
  if not is_readable(tmp) then
    return nil, "Download failed (curl/cp could not fetch the guide)"
  end

  if is_gzip_file(tmp) then
    os.execute("gzip -dc " .. shell_quote(tmp) .. " > " .. shell_quote(out))
    os.remove(tmp)
    if not is_readable(out) then return nil, "Could not decompress the guide (gzip failed)" end
    return out
  end
  return tmp
end

local function fetch_epg(src)
  local s, oerr = open_stream(src)
  local progs, name_map, err
  if s then progs, name_map, err = parse_epg_stream(s) end
  if progs then return progs, name_map end

  if s == nil or err == "gzip" then
    set_status("Fetching guide with curl...")
    local path, serr = shell_fetch(src)
    if not path then return nil, serr end
    local s2 = vlc.stream(vlc.strings.make_uri(path))
    if not s2 then
      os.remove(path)
      return nil, "Cannot open the downloaded guide"
    end
    progs, name_map, err = parse_epg_stream(s2)
    os.remove(path)
    if not progs then return nil, "Guide is still compressed after gunzip" end
    return progs, name_map
  end
  return nil, err or ("Cannot open guide: " .. tostring(oerr or src))
end

---------------------------------------------------------------------------
-- Guide cache
---------------------------------------------------------------------------

local function playlist_signature()
  local MOD = 2147483629
  local h = 7
  local function add(str)
    for i = 1, #str do h = (h * 31 + str:byte(i)) % MOD end
  end
  for _, ch in ipairs(state.channels) do
    add(ch.tvg_id); add("|"); add(ch.norm); add("|"); add(ch.loose); add(";")
  end
  return tostring(h) .. ":" .. #state.channels
end

local function flat(s)
  return (tostring(s or ""):gsub("[\t\r\n]", " "))
end

local function save_cache(src, sig, progs, name_map)
  local f = io.open(data_path(CACHE_NAME), "w")
  if not f then return end
  f:write("#v3\t", os.time(), "\t", flat(src), "\t", sig, "\n")
  for n, id in pairs(name_map) do
    f:write("N\t", n, "\t", flat(id), "\n")
  end
  for id, list in pairs(progs) do
    for _, p in ipairs(list) do
      f:write("P\t", flat(id), "\t", p.start, "\t", p.stop, "\t",
              flat(p.title), "\t", flat(p.desc), "\t", flat(p.cat), "\n")
    end
  end
  f:close()
end

local function load_cache(src, sig)
  local f = io.open(data_path(CACHE_NAME), "r")
  if not f then return nil end
  local header = f:read("*l")
  local tag, ts, csrc, csig = (header or ""):match("^(#v3)\t(%d+)\t([^\t]*)\t([^\t]*)$")
  if not tag or csrc ~= flat(src) or csig ~= sig then
    f:close()
    return nil
  end
  local progs, name_map = {}, {}
  for line in f:lines() do
    local kind = line:sub(1, 1)
    if kind == "P" then
      local id, st, en, title, desc, cat =
        line:match("^P\t([^\t]*)\t(%d+)\t(%d+)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
      if id then
        local list = progs[id]
        if not list then list = {}; progs[id] = list end
        list[#list + 1] = {
          start = tonumber(st), stop = tonumber(en),
          title = decode_text(title), desc = decode_text(desc), cat = decode_text(cat),
        }
      end
    elseif kind == "N" then
      local n, id = line:match("^N\t([^\t]*)\t([^\t]*)$")
      if n then name_map[n] = id end
    end
  end
  f:close()
  for _, list in pairs(progs) do
    table.sort(list, function(a, b) return a.start < b.start end)
  end
  return progs, name_map, tonumber(ts)
end

---------------------------------------------------------------------------
-- Guide lookup
---------------------------------------------------------------------------

local function apply_epg()
  local progs, map = state.progs, state.name_map
  state.stats = { id = 0, name = 0 }
  for _, ch in ipairs(state.channels) do
    local id, how = nil, nil
    if ch.tvg_id ~= "" then
      if progs[ch.tvg_id] then
        id, how = ch.tvg_id, "id"
      else
        local m = map["i:" .. canon_id(ch.tvg_id)]
        if m and progs[m] then id, how = m, "id" end
      end
    end
    if not id and ch.norm ~= "" then
      local m = map["n:" .. ch.norm]
      if m and progs[m] then id, how = m, "name" end
    end
    if not id and ch.loose ~= "" and not ch.loose_ambiguous then
      local m = map["l:" .. ch.loose]
      if m and progs[m] then id, how = m, "name" end
    end
    ch.epg = id
    if how then state.stats[how] = state.stats[how] + 1 end
  end
end

local function now_next(ch, t)
  if not ch.epg then return nil, nil end
  local list = state.progs[ch.epg]
  if not list then return nil, nil end
  for i = 1, #list do
    local p = list[i]
    if p.stop > t then
      if p.start <= t then return p, list[i + 1] end
      return nil, p
    end
  end
  return nil, nil
end

---------------------------------------------------------------------------
-- Loading pipeline
---------------------------------------------------------------------------

local function guide_summary()
  local matched, programs = 0, 0
  for _, ch in ipairs(state.channels) do
    if ch.epg then matched = matched + 1 end
  end
  for _, list in pairs(state.progs) do programs = programs + #list end
  if programs == 0 then
    return "guide: no programs found for your channels (check tvg-id values / guide source)"
  end
  local st = state.stats or { id = 0, name = 0 }
  return string.format("guide: %d programs, %d of %d channels matched (%d by id, %d by name)",
                       programs, matched, #state.channels, st.id, st.name)
end

local function load_guide(force)
  state.progs, state.name_map = {}, {}
  state.guide_note = ""
  local src = state.epg
  if src == "" then src = state.header_epg or "" end
  if src == "" then
    apply_epg()
    state.guide_note = "no guide source set (Settings)"
    return
  end

  local sig = playlist_signature()
  local cp, cn, ts = load_cache(src, sig)
  local fresh = cp and next(cp) ~= nil and ts and (os.time() - ts) < EPG_TTL

  if cp and fresh and not force then
    state.progs, state.name_map = cp, cn
    apply_epg()
    state.guide_note = guide_summary() .. " (cached)"
    return
  end

  set_status("Downloading guide...")
  local ok, p, n = pcall(fetch_epg, src)
  if ok and p then
    state.progs, state.name_map = p, n
    save_cache(src, sig, p, n)
    apply_epg()
    state.guide_note = guide_summary()
  elseif cp then
    state.progs, state.name_map = cp, cn
    apply_epg()
    state.guide_note = "guide update failed, using cache. " .. guide_summary()
  else
    local err = ok and n or p
    apply_epg()
    state.guide_note = "guide failed: " .. tostring(err)
  end
end

---------------------------------------------------------------------------
-- OSD
---------------------------------------------------------------------------

local function osd_for(ch)
  if not ch then return end
  if not state.osd then state.osd = vlc.osd.channel_register() end
  local t = os.time()
  local cur, nxt = now_next(ch, t)
  local lines = { ch.name }
  if cur then
    local head = string.format("NOW  %s-%s  %s", fmt_time(cur.start), fmt_time(cur.stop), cur.title)
    if cur.cat and cur.cat ~= "" then head = head .. "  [" .. cur.cat .. "]" end
    lines[#lines + 1] = head
    if cur.desc and cur.desc ~= "" then
      local text = cur.desc
      if #text > OSD_SYNOPSIS_CHARS then text = text:sub(1, OSD_SYNOPSIS_CHARS) .. "..." end
      lines[#lines + 1] = text
    end
  end
  if nxt then
    lines[#lines + 1] = string.format("NEXT %s  %s", fmt_time(nxt.start), nxt.title)
  end
  vlc.osd.message(table.concat(lines, "\n"), state.osd, "top-left", OSD_DURATION)
end

---------------------------------------------------------------------------
-- Playlist export
---------------------------------------------------------------------------

-- VLC columns are plain text, so "bold" is done with Unicode bold characters.
-- Only ASCII letters and digits are converted; other characters stay as they are.
local function to_bold(str)
  return (str:gsub("[A-Za-z0-9]", function(c)
    local b = c:byte()
    if b >= 65 and b <= 90 then return utf8_char(0x1D5D4 + b - 65) end
    if b >= 97 and b <= 122 then return utf8_char(0x1D5EE + b - 97) end
    return utf8_char(0x1D7EC + b - 48)
  end))
end

local function build_description(ch, t)
  local list = ch.epg and state.progs[ch.epg]
  if not list then return "" end
  local opt = DISPLAY_BY_ID[state.display] or DISPLAY_BY_ID[DEFAULT_DISPLAY]
  local by_hours = opt.mode == "hours"
  local horizon = by_hours and (t + opt.n * 3600) or nil
  local limit = by_hours and MAX_PROGRAMS or opt.n

  local parts, truncated = {}, false
  for i = 1, #list do
    local p = list[i]
    if p.stop > t then
      local running = p.start <= t
      if horizon and not running and p.start >= horizon then break end
      if #parts >= limit then
        truncated = by_hours
        break
      end
      if #parts == 0 and running then
        local now_text = string.format("%s-%s %s",
          fmt_time(p.start), fmt_time(p.stop), p.title)
        if BOLD_CURRENT then now_text = to_bold(now_text) end
        parts[#parts + 1] = now_text
      else
        parts[#parts + 1] = string.format("%s %s", fmt_time(p.start), p.title)
      end
    end
  end

  local text = table.concat(parts, SEPARATOR)
  if truncated then text = text .. SEPARATOR .. "..." end
  return text
end

local function load_into_playlist(force_epg)
  if state.m3u == "" then
    set_status("Enter the playlist address first.")
    return
  end
  set_status("Loading playlist...")
  local ok, channels, groups, by_url, header_epg, info = pcall(parse_m3u, state.m3u)
  if not ok then
    set_status("Playlist failed: " .. tostring(channels))
    return
  end
  if not channels then
    set_status(tostring(groups))
    return
  end
  if #channels == 0 then
    if info.lines == 0 then
      set_status("The playlist source returned no data. Check the path or URL.")
    else
      set_status(string.format("No channels found. Read %d lines, first line: \"%s\"",
                               info.lines, info.first))
    end
    return
  end
  state.channels, state.groups, state.by_url, state.header_epg =
    channels, groups, by_url, header_epg

  load_guide(force_epg)

  local t = os.time()
  local items = {}
  for _, ch in ipairs(state.channels) do
    local item = {
      path = ch.url,
      name = ch.name,
      title = ch.name,
      artist = ch.group,
      description = build_description(ch, t),
    }
    local cur = now_next(ch, t)
    if GENRE_FROM_CATEGORY then
      if cur and cur.cat and cur.cat ~= "" then item.genre = cur.cat end
    else
      item.genre = ch.group
    end
    if ALBUM_FROM_SYNOPSIS and cur and cur.desc and cur.desc ~= "" then
      item.album = cur.desc
    end
    items[#items + 1] = item
  end

  vlc.playlist.clear()
  vlc.playlist.add(items)

  local opt = DISPLAY_BY_ID[state.display] or DISPLAY_BY_ID[DEFAULT_DISPLAY]
  local msg = string.format("%d channels added (%s).", #items, opt.label)
  if state.guide_note ~= "" then msg = msg .. " " .. state.guide_note end
  set_status(msg)
end

---------------------------------------------------------------------------
-- Dialog
---------------------------------------------------------------------------

local function strip_quotes(s)
  s = trim(s)
  return (s:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1"))
end

local function read_fields()
  state.m3u = strip_quotes(ui.in_m3u:get_text())
  state.epg = strip_quotes(ui.in_epg:get_text())
  if ui.display then
    local id = ui.display:get_value()
    if type(id) == "number" and DISPLAY_BY_ID[id] then state.display = id end
  end
  save_config()
end

local function on_load()
  read_fields()
  load_into_playlist(false)
end

local function on_refresh()
  read_fields()
  load_into_playlist(true)
end

local function create_dialog()
  local d = vlc.dialog("VLC EPG")
  ui.dialog = d
  ui.status = d:add_label("Enter your playlist, then press Load.", 1, 1, 8, 1)
  d:add_label("Playlist: M3U file path or URL", 1, 2, 8, 1)
  ui.in_m3u = d:add_text_input(state.m3u, 1, 3, 8, 1)
  d:add_label("Guide: XMLTV file path or URL (optional)", 1, 4, 8, 1)
  ui.in_epg = d:add_text_input(state.epg, 1, 5, 8, 1)
  d:add_label("Show in Description:", 1, 6, 3, 1)
  ui.display = d:add_dropdown(4, 6, 5, 1)
  -- The saved choice goes first, because it is the one selected by default.
  local current = DISPLAY_BY_ID[state.display] or DISPLAY_BY_ID[DEFAULT_DISPLAY]
  ui.display:add_value(current.label .. " (current)", current.id)
  for _, opt in ipairs(DISPLAY_OPTIONS) do
    if opt.id ~= current.id then ui.display:add_value(opt.label, opt.id) end
  end
  d:add_button("Load into playlist", on_load, 1, 7, 4, 1)
  d:add_button("Re-download guide", on_refresh, 5, 7, 4, 1)
  d:update()
end

---------------------------------------------------------------------------
-- VLC extension entry points
---------------------------------------------------------------------------

function descriptor()
  return {
    title = "VLC EPG 2.2",
    version = "2.2.0",
    author = "Yasser Mahmoud",
    shortdesc = "VLC EPG",
    description = "Loads an M3U playlist and fills the playlist columns with XMLTV program info.",
    capabilities = { "input-listener" },
  }
end

function activate()
  load_config()
  create_dialog()
end

function deactivate()
  if ui.dialog then pcall(function() ui.dialog:delete() end) end
  ui = {}
end

function close()
  vlc.deactivate()
end

function input_changed()
  pcall(function()
    local item = vlc.input.item()
    if not item then return end
    local uri = item:uri()
    local ch = state.by_url[uri]
    if not ch and vlc.strings and vlc.strings.decode_uri then
      ch = state.by_url[vlc.strings.decode_uri(uri)]
    end
    if ch then osd_for(ch) end
  end)
end

print("InkgloSpace Was Here!")

-- curl.exe --digest -u User:Pass -X POST "http://IP/api/player/play"
-- testing klo mau cek endpoint dari powershell

local HttpClient = require("HttpClient")
local json       = require("json")

--setup
local IP, PORT   = "192.168.100.99", 80 --vp320
local USER, PASS = "admin", "1312" --digest auth
local TIMEOUT  = 5
local PLAYER  = "api/player" --path API player

-- debug log
local function log(_, code, data, err, headers)
  print(("HTTP: %s  ERR: %s"):format(tostring(code), err or ""))
  if headers and headers["content-type"] then print("CT:", headers["content-type"]) end
  if data and #data > 0 then
    local ok, parsed = pcall(json.decode, data)
    if ok and type(parsed)=="table" then
      print("BODY(JSON):", json.encode(parsed, { pretty = true }))
    else
      print("BODY:", data)
    end
  end
end

-- http untuk post
local function postEmpty(path)
  local url = HttpClient.CreateUrl{ Scheme="http", Host=IP, Port=PORT, Path=path }
  HttpClient.Post{
    Url          = url,
    User         = USER,
    Password     = PASS,
    Auth         = "digest",
    Timeout      = TIMEOUT,
    Headers      = { ["Content-Type"]="application/x-www-form-urlencoded",
                     ["Content-Length"]="0" },
    Data         = "",
    EventHandler = log,
  }
end

-- http untuk post pake query (untuk play folder)
local function postEmptyWithQuery(path, q)
  HttpClient.Post{
    Url       = HttpClient.CreateUrl{ Scheme="http", Host=IP, Port=PORT, Path=path, Query=q },
    User      = USER,
    Password  = PASS,
    Auth      = "digest",
    Timeout   = TIMEOUT,
    Headers   = { ["Content-Type"]="application/x-www-form-urlencoded",
                  ["Content-Length"]="0" },
    Data      = "",
    EventHandler = log
  }
end

-- http untuk post fader volume
local function postForm(path, kv)
  HttpClient.Post{
    Url       = HttpClient.CreateUrl{ Scheme="http", Host=IP, Port=PORT, Path=path },
    User      = USER,
    Password  = PASS,
    Auth      = "digest",
    Timeout   = TIMEOUT,
    Headers   = { ["Content-Type"] = "application/x-www-form-urlencoded" },
    Data      = HttpClient.EncodeParams(kv),
    EventHandler = log
  }
end

-- setup fader absolute
local function clampRound100(v)
  return math.max(0, math.min(100, math.floor((tonumber(v) or 0) + 0.5)))
end

local function SetVolumeFromFader(raw)
  local target = clampRound100(raw)
  -- absolute set: /api/player/set-volume  body: volume=<0..100>&relative=false
  postForm(PLAYER.."/set-volume", {
    volume   = tostring(target),
    relative = "false"
  })
  -- optional: log simpel
  print(("VOL ABS -> %d"):format(target))
end


-- endpoint player
local function Play()  postEmpty(PLAYER.."/play")  end
local function Pause() postEmpty(PLAYER.."/play-pause") end
local function Stop()  postEmpty(PLAYER.."/stop")  end
local function Next()  postEmpty(PLAYER.."/next-file")  end
local function muteUnmute()  postEmpty(PLAYER.."/toggle-mute")  end
-- endpoint play folder
local function PlayFolder(n) postEmptyWithQuery(PLAYER.."/play-folder", { folder = tostring(n) }) end

-- GET SYSTEM STATE
local SYS_PATH = "api/system/state/playbackengine"

-- setup untuk tipe output
local function setOutNumber(idx, val)
  local o = Controls.Outputs[idx]; if not o then return end
  o.Value = tonumber(val) or 0
end
local function setOutBool(idx, b)
  local o = Controls.Outputs[idx]; if not o then return end
  o.Value = (b and 1) or 0
end
local function setOutText(idx, s)
  local o = Controls.Outputs[idx]; if not o or o.String == nil then return end
  o.String = tostring(s or "")
end

-- tampilkan format jam
local function hhmmss(sec)
  sec = math.max(0, tonumber(sec) or 0)
  local h = math.floor(sec / 3600)
  local m = math.floor((sec % 3600) / 60)
  local s = math.floor(sec % 60)
  return string.format("%02d:%02d:%02d", h, m, s)
end

-- folder "000","001",...
local function zpad3(n) 
  n = tonumber(n) or 0
  return string.format("%03d", n)
end

local function applyPlaybackEngine(obj)
  -- obj = { data = { state, folder={index}, file={name,duration,position}, audio={volume,mute} } }
  local data     = obj and obj.data or {}
  local stateStr = data.state
  local folder   = data.folder or {}
  local file     = data.file   or {}
  local audio    = data.audio  or {}

  local isPlaying = (type(stateStr)=="string" and stateStr:lower()=="playing") or false
  local fIndex    = tonumber(folder.index)   or 0
  local name      = tostring(file.name or "")
  local duration  = tonumber(file.duration)  or 0
  local position  = tonumber(file.position)  or 0
  local vol       = tonumber(audio.volume)   or 0
  local isMuted   = (audio.mute == true)

  setOutBool(1, true)               -- Connected
  setOutBool(2, isPlaying)          -- IsPlaying
  setOutText(3, zpad3(fIndex))      -- FolderIndex
  setOutText(4, name)               -- NowPlayingName (Text Output)
  setOutText(7, tostring(vol).."%") -- Volume (0..100) / setOutText(7, tostring(vol))
  setOutBool(8, isMuted)                -- IsMuted
  
  if Controls.Outputs[5] and Controls.Outputs[5].String ~= nil then
    setOutText(5, hhmmss(position))
  end
  if Controls.Outputs[6] and Controls.Outputs[6].String ~= nil then
    setOutText(6, hhmmss(duration))
  end

  --[[print(string.format("PE: %s | folder=%s | pos=%s / %s | vol=%d | mute=%s | file=%s",
  stateStr or "?", zpad3(fIndex), hhmmss(position), hhmmss(duration),
  vol, tostring(isMuted), name))
  ]]
  
end

-- loop state GET -> start script langsung panggil lagi
local function StateLoop()
  HttpClient.Get{
    Url       = HttpClient.CreateUrl{ Scheme="http", Host=IP, Port=PORT, Path=SYS_PATH },
    User      = USER, Password = PASS, Auth = "digest",
    Timeout   = TIMEOUT,   -- mis. 5 detik
    EventHandler = function(_, code, data, err)
      if code == 200 and data and #data > 0 then
        local ok, obj = pcall(json.decode, data)
        if ok and type(obj) == "table" then
          applyPlaybackEngine(obj)
        else
          -- payload bukan JSON yang diharapkan, tetap tandai connected
          setOutBool(1, true)
        end
      else
        -- error/timeout: tandai disconnect, lalu lanjut loop
        setOutBool(1, false)
        setOutBool(2, false)
        if err then print("State GET error:", err) end
      end

      StateLoop()
    end
  }
end
-- end GET SYSTEM STATE

-- maping pin 
local pinMap = {
  [1] = Play,  
  [2] = Pause,
  [3] = Stop,
  [4] = Next,
  [5] = muteUnmute,
  [7] = function() PlayFolder(0) end,
  [8] = function() PlayFolder(1) end,
  [9] = function() PlayFolder(2) end,
  [10] = function() PlayFolder(3) end
}

-- input pin
for i, fn in pairs(pinMap) do
  local pin = Controls.Inputs[i]
  if pin then
    pin.EventHandler = function(c)
      
      if c.Boolean == true then fn() end
    end
  end
end

-- fader di Input pin 6 → set volume absolute
if Controls.Inputs[6] then
  Controls.Inputs[6].EventHandler = function(c)
    SetVolumeFromFader(c.Value or 0)
  end
end
--state loop
StateLoop()
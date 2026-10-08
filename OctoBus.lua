--[[
  OctoBus
  -------
  Arrival timers for the zeppelins at the Orgrimmar towers (plus the Sparkwater Port boat).
  A small icon on the minimap edge shows / hides a timer window; the window opens by itself
  in Orgrimmar and Durotar.

  HOW IT WORKS
  Needs ZepSense.dll (listed in dlls.txt). The DLL adds one function to the client,
  ZepTransports(), which returns the position of every zeppelin/boat the client has loaded.
  This addon polls it, watches each transport arrive at / leave its dock, and keeps a
  schedule: every route runs on a fixed cycle length, so one observed arrival predicts all
  later ones, even while the transport is out of sight.

  A "~" in front of a time means that time is still an estimate from stored data and has not
  been confirmed by seeing the transport dock this session. After the transport is seen
  docking (or leaving), the "~" disappears.

  Click a row to put a bell on it: you then get a chat message before that transport arrives.

  SLASH COMMANDS  (/ob, also /transit and /zep)
    /ob                     show / hide the window (works anywhere)
    /ob list                print all timers in chat
    /ob alert <sec>         bell alerts fire this many seconds before arrival (default 45)
    /ob sound|chat|flash    toggle that alert type
    /ob zone                toggle "auto-show only in Orgrimmar / Durotar"
    /ob boat                show / hide the Sparkwater Port boat
    /ob shape square|round|auto   minimap icon placement (auto looks at your minimap)
    /ob where               print your zone / sub-zone and whether the window auto-shows
    /ob allow <name>        also auto-show in this zone or sub-zone
    /ob name <n> <text>     rename route number n (from /ob list)
    /ob period <n> <sec>    set a route's cycle length by hand
    /ob calibrate           optional: watch every transport on purpose (stand between the towers).
                            Not required: any arrival you see near the towers calibrates automatically.
    /ob reset               forget everything learned (back to built-in values)
    /ob debug               show what the DLL is returning
]]

-- Stage 1: runs as soon as this file loads, so /ob always answers, even if the real
-- start-up below fails. If it fails, /ob prints the error message.
local OB_STAGE = "file loaded, start-up not finished"
SLASH_OCTOBUS1 = "/ob"
SLASH_OCTOBUS2 = "/transit"
SLASH_OCTOBUS3 = "/zep"
SlashCmdList["OCTOBUS"] = function(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccOctoBus:|r not running. " .. tostring(OB_STAGE))
end

local OB_OK, OB_ERR = pcall(function ()

  local gfind = string.gmatch or string.gfind

  ------------------------------------------------------------------------
  -- Routes. x,y = where the transport stands while docked (measured in-game).
  -- period/anchor are starting values measured from a 25 minute log; anchor is the
  -- time() of one observed arrival. Real observations replace them automatically.
  ------------------------------------------------------------------------
  local ROUTES = {
    { entry = 164871, name = "Undercity", x = 1318.1, y = -4658.0, period = 356.3, dwell = 63, anchor = 1791422404 },
    { entry = 175080, name = "Grom'gol", x = 1360.8, y = -4631.3, period = 303.5, dwell = 63, anchor = 1791422441 },
    { entry = 190552, name = "Kargath", x = 1206.1, y = -4158.7, period = 374.0, dwell = 63, anchor = 1791422484 },
    { entry = 190549, name = "Thunder Bluff", x = 1125.4, y = -4135.0, period = 567.0, dwell = 63, anchor = 1791422131 },
    { entry = 190550, name = "Sparkwater boat", x = 876.1,  y = -5204.1, period = 244.75, dwell = 43, anchor = 1791422323, boat = true },
  }
  local DOCK_RADIUS = 2.0

  ------------------------------------------------------------------------
  -- Saved data
  ------------------------------------------------------------------------
  -- The game loads saved variables AFTER an addon's files have run (replacing the global),
  -- so the saved table is looked up on every access and its defaults are filled in
  -- whenever it changes.
  local G = getfenv(0)
  local dbRef = nil
  local function Ensure()
    local t = G.OctoBusDB
    if type(t) ~= "table" then
      t = {}
      G.OctoBusDB = t
    end
    if t ~= dbRef then
      dbRef = t
      t.anchor = t.anchor or {}
      t.period = t.period or {}
      t.names = t.names or {}
      t.bell = t.bell or {}
      t.origin = t.origin or {}
      t.dwell = t.dwell or {}
      t.lastObs = t.lastObs or {}
      t.cfg = t.cfg or {}
      local c = t.cfg
      if c.alert == nil then c.alert = 45 end
      if c.chat == nil then c.chat = true end
      if c.sound == nil then c.sound = false end
      if c.flash == nil then c.flash = false end
      if c.zoneOnly == nil then c.zoneOnly = true end
      c.allow = c.allow or {}
      if c.hideBoat == nil then c.hideBoat = false end
      if c.locked == nil then c.locked = false end
      if c.ver ~= 2 then   -- v2: alerts are opt-in per route (bell) and chat-only by default
        c.ver = 2
        c.chat = true
        c.sound = false
        c.flash = false
      end
    end
    return t
  end
  local DB = setmetatable({}, {
    __index = function(_, k) return Ensure()[k] end,
    __newindex = function(_, k, v) Ensure()[k] = v end,
  })
  local CFG = setmetatable({}, {
    __index = function(_, k) return Ensure().cfg[k] end,
    __newindex = function(_, k, v) Ensure().cfg[k] = v end,
  })
  Ensure()

  local function Say(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccOctoBus:|r " .. msg)
  end

  local function FormatTime(s)
    s = math.floor(s + 0.5)
    if s < 0 then s = 0 end
    return string.format("%d:%02d", math.floor(s / 60), math.mod(s, 60))
  end

  local function RouteName(r) return DB.names[r.entry] or r.name end
  local function Period(r)    return DB.period[r.entry] or r.period end
  local function Anchor(r)    return DB.anchor[r.entry] or r.anchor end
  local function Watched(r)   return DB.bell[r.entry] == true end
  local function Visible(r)   return (not r.boat) or (not CFG.hideBoat) end

  -- confirmed[entry] = true once the transport has been SEEN docking/leaving this session
  local confirmed = {}

  ------------------------------------------------------------------------
  -- Clock: epoch seconds with sub-second precision. time() only ticks whole seconds,
  -- so remember the largest (time() - GetTime()) seen: that converges on the true offset.
  ------------------------------------------------------------------------
  local clockC = nil
  local function EpochNow()
    local g = GetTime()
    local c = time() - g
    if (not clockC) or c > clockC then clockC = c end
    return g + clockC
  end

  local function Dwell(r) return DB.dwell[r.entry] or r.dwell end

  -- returns "docked", secondsUntilDeparture   or   "wait", secondsUntilArrival
  local function Predict(r)
    local a, P = Anchor(r), Period(r)
    if not a or not P or P <= 0 then return nil end
    local e = EpochNow() - a
    local ph = math.mod(e, P)
    if ph < 0 then ph = ph + P end
    local d = Dwell(r)
    if ph < d then return "docked", d - ph end
    return "wait", P - ph
  end

  ------------------------------------------------------------------------
  -- Calibration. /ob calibrate: stay somewhere you can see the docks (between the two
  -- towers). Every route needs one fresh arrival (two the very first time, because a
  -- cycle length needs two arrivals to measure). Each new arrival is compared with the
  -- oldest trusted one (the "origin"): the gap divided by the whole number of cycles in
  -- it gives the cycle length, and the longer the gap, the more exact it gets.
  ------------------------------------------------------------------------
  local cal = nil        -- nil = not calibrating

  -- Every arrival that refines a cycle length counts as a calibration for that route,
  -- whether you ran /ob calibrate or just walked past the towers.
  local function FormatSpan(sec)
    if sec < 3600 then return string.format("%d min", math.floor(sec / 60 + 0.5)) end
    if sec < 86400 then return string.format("%.0f h", sec / 3600) end
    return string.format("%.1f days", sec / 86400)
  end

  -- footer text, and whether it should be highlighted
  local function CalAgeText()
    local newestOld, shortest, have, total = nil, nil, 0, 0
    local now = time()
    for i = 1, table.getn(ROUTES) do
      local r = ROUTES[i]
      if Visible(r) then
        total = total + 1
        local t = DB.lastObs[r.entry]
        local o = DB.origin[r.entry]
        if t and o then
          have = have + 1
          if not newestOld or t < newestOld then newestOld = t end      -- longest since seen
          local span = EpochNow() - o
          if not shortest or span < shortest then shortest = span end   -- thinnest baseline
        end
      end
    end
    if have == 0 then return "no baseline yet (visit the towers)", true end
    if have < total then return "baseline: " .. have .. " of " .. total .. " transports", true end
    local gone = now - newestOld
    local seen
    if gone < 3600 then seen = "seen just now"
    elseif gone < 86400 then seen = "last seen " .. string.format("%.0f", gone / 3600) .. " h ago"
    else seen = "last seen " .. string.format("%d", math.floor(gone / 86400 + 0.5)) .. "d ago" end
    local stale = (gone >= 5 * 86400)
    if stale then seen = seen .. ", visit the towers" end
    return "baseline established: " .. FormatSpan(shortest) .. "  (" .. seen .. ")", stale
  end

  local function CalFinish(complete)
    if not cal then return end
    Say(complete and "calibration complete." or "calibration stopped.")
    for i = 1, table.getn(ROUTES) do
      local r = ROUTES[i]
      if cal.need[r.entry] then
        local oldP = cal.oldP[r.entry]
        local done = (cal.got[r.entry] or 0) >= cal.need[r.entry]
        Say("  " .. RouteName(r) .. ": cycle " .. string.format("%.2f", Period(r)) .. "s" ..
          (oldP and (math.abs(oldP - Period(r)) > 0.005 and ("  (was " .. string.format("%.2f", oldP) .. ")") or "  (unchanged)") or "") ..
          (done and "" or "   - not seen, still using the old value"))
      end
    end
    if complete then
      Say("done. The window footer tracks how fresh this is; it nags after 5 days.")
    end
    cal = nil
  end

  local function CalObs(r, rebased)
    if not cal or not cal.need[r.entry] then return end
    local e = r.entry
    if rebased then
      cal.need[e] = (cal.got[e] or 0) + 1      -- the old baseline did not fit: measure again
      return
    end
    cal.got[e] = (cal.got[e] or 0) + 1
    local all = true
    for k, n in pairs(cal.need) do
      if (cal.got[k] or 0) < n then all = false end
    end
    if all then CalFinish(true) end
  end

  local function CalStart()
    cal = { need = {}, got = {}, oldP = {}, t0 = GetTime() }
    local n = 0
    for i = 1, table.getn(ROUTES) do
      local r = ROUTES[i]
      if Visible(r) then
        cal.need[r.entry] = DB.origin[r.entry] and 1 or 2
        cal.oldP[r.entry] = Period(r)
        n = n + 1
      end
    end
    return n
  end

  local function CalCount()
    local done, total = 0, 0
    if not cal then return 0, 0 end
    for k, n in pairs(cal.need) do
      total = total + 1
      if (cal.got[k] or 0) >= n then done = done + 1 end
    end
    return done, total
  end

  ------------------------------------------------------------------------
  -- Watching the DLL
  ------------------------------------------------------------------------
  local seenState = {}   -- entry -> { atDock = bool, arrivedAt = epoch or nil }
  local dllOk = false
  local lastGood = 0

  local function OnArrive(r, t)
    local e = r.entry
    local P = Period(r)
    local pstate, psecs = Predict(r)
    local origin = DB.origin[e]
    local rebased = false
    if origin then
      local delta = t - origin
      local k = math.floor(delta / P + 0.5)
      local resid = delta - k * P
      if k >= 1 and math.abs(resid) < 0.25 * P then
        DB.period[e] = delta / k
        DB.lastObs[e] = time()
      else
        DB.origin[e] = t      -- schedule jumped (server restart?): start a new baseline
        rebased = true
      end
    else
      DB.origin[e] = t
    end
    -- how far off was the schedule?
    if pstate and not confirmed[e] and CFG.chat and Watched(r) then
      local off
      if pstate == "docked" then off = Dwell(r) - psecs else off = -psecs end
      if pstate == "wait" and psecs < P / 2 then off = psecs end
      if math.abs(off) > 20 then
        Say(RouteName(r) .. ": schedule re-synced from what I just saw (was off by about " ..
          string.format("%d", math.floor(math.abs(off) + 0.5)) .. "s).")
      end
    end
    DB.anchor[e] = t
    confirmed[e] = true
    CalObs(r, rebased)
  end

  local function OnDepart(r, t, st)
    local e = r.entry
    if st.arrivedAt then
      local d = t - st.arrivedAt
      if d > 20 and d < 150 then
        DB.dwell[e] = DB.dwell[e] and (DB.dwell[e] * 0.6 + d * 0.4) or d
      end
    else
      -- never saw it arrive, but it leaves 'dwell' seconds after arriving
      DB.anchor[e] = t - Dwell(r)
      if not DB.origin[e] then
        DB.origin[e] = t - Dwell(r)
        CalObs(r, false)
      end
    end
    confirmed[e] = true
  end

  local function Poll()
    if type(ZepTransports) ~= "function" then dllOk = false; return end
    local ok, str = pcall(ZepTransports)
    if not ok or type(str) ~= "string" then dllOk = false; return end
    dllOk = true
    lastGood = GetTime()
    local now = EpochNow()
    local present = {}
    for rec in gfind(str, "([^;]+);") do
      local _, _, tag, ge, de, x, y = string.find(rec, "^%x+,(%x+),(%d+),(%d+),(%-?[%d%.]+),(%-?[%d%.]+),")
      de = tonumber(de)
      x = tonumber(x)
      y = tonumber(y)
      if de and x and y then
        for i = 1, table.getn(ROUTES) do
          local r = ROUTES[i]
          if r.entry == de then
            present[de] = true
            local dx, dy = x - r.x, y - r.y
            local atDock = (math.sqrt(dx * dx + dy * dy) <= DOCK_RADIUS)
            local st = seenState[de]
            if not st then
              seenState[de] = { atDock = atDock }
              if cal then cal.seenAny = true end
            else
              if atDock and not st.atDock then
                st.atDock = true
                st.arrivedAt = now
                OnArrive(r, now)
              elseif (not atDock) and st.atDock then
                st.atDock = false
                OnDepart(r, now, st)
                st.arrivedAt = nil
              end
            end
          end
        end
      end
    end
    -- forget transports that left view so the next sighting starts clean
    for i = 1, table.getn(ROUTES) do
      local e = ROUTES[i].entry
      if seenState[e] and not present[e] then seenState[e] = nil end
    end
  end

  ------------------------------------------------------------------------
  -- Frames
  ------------------------------------------------------------------------
  local font = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
  local anchorTo = Minimap

  -- flat dark panel with a thin border
  local function CreateBackdrop(f)
    f:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8X8",
      edgeFile = "Interface\\Buttons\\WHITE8X8",
      tile = false, tileSize = 0, edgeSize = 1,
      insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    f:SetBackdropColor(0.02, 0.02, 0.02, 0.92)
    f:SetBackdropBorderColor(0.22, 0.22, 0.22, 1)
  end

  -- square or round minimap? "auto" looks at the minimap: the stock UI keeps it inside
  -- MinimapCluster; a replacement UI that moves it elsewhere is assumed to have made it square.
  local function MinimapIsSquare()
    if CFG.shape == "square" then return true end
    if CFG.shape == "round" then return false end
    if GetMinimapShape then return GetMinimapShape() == "SQUARE" end
    return Minimap:GetParent() ~= MinimapCluster
  end

  local ICON_HERE = "Interface\\Buttons\\UI-CheckBox-Check"
  local ICON_AWAY = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"

  -- minimap icon: click = show / hide the window, drag = move it around the minimap edge
  local btn = CreateFrame("Button", "OctoBusButton", Minimap)
  btn:SetFrameStrata("MEDIUM")
  btn:SetFrameLevel(Minimap:GetFrameLevel() + 8)
  btn:SetWidth(31)
  btn:SetHeight(31)
  btn:RegisterForClicks("LeftButtonUp")
  btn:RegisterForDrag("LeftButton")
  btn.icon = btn:CreateTexture(nil, "ARTWORK")
  btn.icon:SetWidth(20)
  btn.icon:SetHeight(20)
  btn.icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 7, -5)
  btn.icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
  btn.border = btn:CreateTexture(nil, "OVERLAY")
  btn.border:SetWidth(53)
  btn.border:SetHeight(53)
  btn.border:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
  btn.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local function PlaceButton()
    local a = CFG.angle or (math.pi * 1.25)   -- default: bottom-left
    local dx, dy = math.cos(a), math.sin(a)
    local w = (anchorTo:GetWidth() or 140) / 2
    local h = (anchorTo:GetHeight() or 140) / 2
    local x, y
    if MinimapIsSquare() then
      -- square minimap: run the icon along the outside of the edge
      local m = math.max(math.abs(dx), math.abs(dy))
      x, y = dx / m * (w + 2), dy / m * (h + 2)
    else
      x, y = dx * (w + 5), dy * (h + 5)
    end
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", anchorTo, "CENTER", x, y)
  end
  PlaceButton()

  btn:SetScript("OnDragStart", function() this.dragging = true end)
  btn:SetScript("OnDragStop", function() this.dragging = false end)
  btn:SetScript("OnUpdate", function()
    if not this.dragging then return end
    local cx, cy = GetCursorPosition()
    local sc = anchorTo:GetEffectiveScale()
    local mx, my = anchorTo:GetCenter()
    if not mx or not my then return end
    CFG.angle = math.atan2(cy / sc - my, cx / sc - mx)
    PlaceButton()
  end)

  -- the timer window
  local WIDTH = 246
  local ROW_H = 18
  local TOP = 22

  local panel = CreateFrame("Frame", "OctoBusPanel", UIParent)
  panel:SetFrameStrata("MEDIUM")
  panel:SetWidth(WIDTH)
  panel:SetHeight(100)
  panel:SetClampedToScreen(true)
  panel:SetMovable(true)
  panel:EnableMouse(true)
  CreateBackdrop(panel)

  panel.title = panel:CreateFontString(nil, "OVERLAY")
  panel.title:SetFont(font, 10, "OUTLINE")
  panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -6)
  panel.title:SetText("|cff33ffccTransports|r")

  panel.status = panel:CreateFontString(nil, "OVERLAY")
  panel.status:SetFont(font, 9, "OUTLINE")
  panel.status:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -7)
  panel.status:SetTextColor(0.6, 0.6, 0.6)

  panel.foot = panel:CreateFontString(nil, "OVERLAY")
  panel.foot:SetFont(font, 9, "OUTLINE")
  panel.foot:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 4)
  panel.foot:SetJustifyH("LEFT")

  local function SavePos()
    local x, y = panel:GetLeft(), panel:GetBottom()
    if x and y then CFG.pos = { x = x, y = y } end
  end

  local function StartDrag()
    if CFG.locked then return end
    panel:StartMoving()
  end
  local function StopDrag()
    panel:StopMovingOrSizing()
    SavePos()
  end
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", StartDrag)
  panel:SetScript("OnDragStop", StopDrag)

  local rows = {}

  local function CreateRow(i)
    local row = CreateFrame("Button", nil, panel)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -(TOP + (i - 1) * ROW_H))
    row:SetPoint("RIGHT", panel, "RIGHT", -4, 0)
    row:RegisterForClicks("LeftButtonUp")
    row:RegisterForDrag("LeftButton")
    row:SetScript("OnDragStart", StartDrag)
    row:SetScript("OnDragStop", StopDrag)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints(row)
    row.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.bg:SetVertexColor(0, 0, 0, 0)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetWidth(14)
    row.icon:SetHeight(14)
    row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)

    row.name = row:CreateFontString(nil, "OVERLAY")
    row.name:SetFont(font, 10, "OUTLINE")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.name:SetJustifyH("LEFT")

    row.time = row:CreateFontString(nil, "OVERLAY")
    row.time:SetFont(font, 10, "OUTLINE")
    row.time:SetPoint("RIGHT", row, "RIGHT", -20, 0)
    row.time:SetJustifyH("RIGHT")

    row.bell = row:CreateTexture(nil, "OVERLAY")
    row.bell:SetWidth(13)
    row.bell:SetHeight(13)
    row.bell:SetPoint("RIGHT", row, "RIGHT", -3, 0)
    row.bell:SetTexture("Interface\\Icons\\INV_Misc_Bell_01")
    row.bell:Hide()

    row:SetScript("OnClick", function()
      if not this.route then return end
      DB.bell[this.route.entry] = (not Watched(this.route)) or nil
      if Watched(this.route) then this.bell:Show() else this.bell:Hide() end
    end)
    row:SetScript("OnEnter", function()
      local r = this.route
      if not r then return end
      GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
      GameTooltip:AddLine(RouteName(r), 1, 1, 1)
      GameTooltip:AddLine("Cycle " .. string.format("%.1f", Period(r)) .. "s, stays " .. string.format("%.0f", Dwell(r)) .. "s   (object " .. r.entry .. ")", 0.7, 0.7, 0.7)
      if DB.origin[r.entry] and DB.anchor[r.entry] then
        local span = DB.anchor[r.entry] - DB.origin[r.entry]
        if span > 60 then
          GameTooltip:AddLine("Cycle measured over " .. (span >= 86400 and string.format("%.1f days", span / 86400) or string.format("%.0f min", span / 60)) .. " of observations.", 0.7, 0.7, 0.7)
        end
      end
      GameTooltip:AddLine(confirmed[r.entry] and "Seen this session: exact." or "Not seen this session: estimate (~).", 0.7, 0.7, 0.7)
      GameTooltip:AddLine("Click: " .. (Watched(r) and "remove the bell (no chat alert)" or "add a bell: chat message " .. CFG.alert .. "s before it arrives"), 0.2, 1, 0.8)
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = row
    return row
  end

  -- returns state ("docked" / "wait" / nil), seconds (may be nil if unknown)
  local function Status(r)
    local ps, psecs = Predict(r)
    local live = seenState[r.entry]
    if live then
      if live.atDock then
        if ps == "docked" then return "docked", psecs end
        return "docked", nil
      else
        if ps == "wait" then return "wait", psecs end
        return "wait", nil
      end
    end
    return ps, psecs
  end

  local function RowText(r)
    local state, secs = Status(r)
    local est = confirmed[r.entry] and "" or "|cff888888~|r"
    local mark = ""
    local nm = mark .. RouteName(r)
    if state == "docked" then
      if secs then
        return nm, state, secs, est .. "|cff55ff55leaves|r |cffffffff" .. FormatTime(secs) .. "|r"
      end
      return nm, state, nil, "|cff55ff55here now|r"
    elseif state == "wait" then
      if secs then
        local color = "|cffffffff"
        if CFG.alert > 0 and secs <= CFG.alert then color = "|cffffaa33" end
        return nm, state, secs, est .. "|cffaaaaaadocks|r " .. color .. FormatTime(secs) .. "|r"
      end
      return nm, state, nil, "|cffaaaaaaarriving...|r"
    end
    return nm, state, nil, "|cff888888--|r"
  end

  local function Refresh()
    local n = 0
    for i = 1, table.getn(ROUTES) do
      local r = ROUTES[i]
      if Visible(r) then
        n = n + 1
        local row = rows[n] or CreateRow(n)
        row:Show()
        row.route = r
        local nm, state, secs, txt = RowText(r)
        if cal and cal.need[r.entry] then
          if (cal.got[r.entry] or 0) >= cal.need[r.entry] then
            nm = "|cff55ff55+|r " .. nm
          else
            nm = "|cffffaa33-|r " .. nm
          end
        end
        row.name:SetText(nm)
        row.time:SetText(txt)
        row.name:SetWidth(WIDTH - 8 - 18 - 4 - 92 - 18)
        if Watched(r) then row.bell:Show() else row.bell:Hide() end
        if state == "docked" then
          row.icon:SetTexture(ICON_HERE)
          row.icon:SetVertexColor(0.3, 1, 0.3)
          row.bg:SetVertexColor(0.1, 0.5, 0.1, 0.35)
        else
          row.icon:SetTexture(ICON_AWAY)
          if secs and CFG.alert > 0 and secs <= CFG.alert then
            row.icon:SetVertexColor(1, 0.7, 0.2)
          else
            row.icon:SetVertexColor(0.6, 0.6, 0.6)
          end
          row.bg:SetVertexColor(0, 0, 0, 0)
        end
      end
    end
    for i = n + 1, table.getn(rows) do rows[i]:Hide() end
    panel:SetHeight(TOP + n * ROW_H + 18)
    panel.status:SetText(dllOk and "" or "no DLL: estimates only")
    if cal then
      local d, t = CalCount()
      local inView = 0
      for i = 1, table.getn(ROUTES) do
        if seenState[ROUTES[i].entry] then inView = inView + 1 end
      end
      if inView > 0 then cal.seenAny = true end
      if inView > 0 then
        panel.foot:SetText("|cffffaa33calibrating " .. d .. "/" .. t .. ": " .. inView .. " in view, stay put|r")
      elseif (not cal.seenAny) and (GetTime() - cal.t0) > 600 then
        -- transports are out of range for part of every cycle, so "none in view" alone
        -- means nothing; only after 10 minutes without a single sighting is it a hint
        panel.foot:SetText("|cffff5555calibrating " .. d .. "/" .. t .. ": nothing seen in 10 min, move closer to the towers|r")
      else
        panel.foot:SetText("|cffffaa33calibrating " .. d .. "/" .. t .. ": waiting for arrivals|r")
      end
    else
      local txt, stale = CalAgeText()
      panel.foot:SetText((stale and "|cffffaa33" or "|cff777777") .. txt .. "" .. "|r")
    end
  end

  local function PlacePanel()
    panel:ClearAllPoints()
    if CFG.pos then
      panel:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", CFG.pos.x, CFG.pos.y)
    else
      panel:SetPoint("TOPRIGHT", anchorTo, "BOTTOMRIGHT", 0, -8)
    end
  end

  -- Auto-show areas: Orgrimmar and Durotar (zone or sub-zone name), plus anything added with /ob allow.
  local function InOrg()
    if not CFG.zoneOnly then return true end
    local z = GetZoneText() or ""
    local sz = GetSubZoneText() or ""
    if z == "Orgrimmar" or sz == "Orgrimmar" or z == "Durotar" or sz == "Durotar" then return true end
    for i = 1, table.getn(CFG.allow) do
      if z == CFG.allow[i] or sz == CFG.allow[i] then return true end
    end
    return false
  end

  -- override: nil = automatic, "show" = forced open anywhere, "hide" = forced closed.
  -- Crossing into or out of the auto-show area puts it back to automatic.
  local override = nil
  local lastArea = nil

  local function ApplyVisibility()
    local area = InOrg()
    if area ~= lastArea then
      lastArea = area
      override = nil
    end
    local want
    if override == "show" then want = true
    elseif override == "hide" then want = false
    else want = area end
    if want then
      if not panel:IsShown() then
        PlacePanel()
        Refresh()
        panel:Show()
      end
      btn.icon:SetVertexColor(1, 1, 1)
    else
      if panel:IsShown() then panel:Hide() end
      btn.icon:SetVertexColor(0.55, 0.55, 0.55)
    end
  end

  local function ToggleShown()
    if panel:IsShown() then override = "hide" else override = "show" end
    ApplyVisibility()
  end

  btn:SetScript("OnClick", function() ToggleShown() end)
  btn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_LEFT")
    GameTooltip:AddLine("Transports", 0.2, 1, 0.8)
    GameTooltip:AddLine("Click: " .. (panel:IsShown() and "hide" or "show") .. " the window (works anywhere)", 1, 1, 1)
    GameTooltip:AddLine("Opens by itself in Orgrimmar and Durotar.", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Drag: move this icon around the minimap", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

  ------------------------------------------------------------------------
  -- Update loop
  ------------------------------------------------------------------------
  local alerted = {}
  local flashUntil = 0
  local pollT, uiT = 0, 0

  local function RunAlerts()
        for i = 1, table.getn(ROUTES) do
      local r = ROUTES[i]
      if Visible(r) then
        local state, secs = Status(r)
        if state == "wait" and secs then
          if Watched(r) then
            if CFG.alert > 0 and secs <= CFG.alert then
              local stamp = math.floor(EpochNow() + secs + 0.5)
              if alerted[r.entry] ~= stamp then
                alerted[r.entry] = stamp
                if CFG.chat then
                  Say(RouteName(r) .. " arrives in " .. FormatTime(secs) .. ".")
                end
                if CFG.sound then PlaySound("RaidWarning") end
                if CFG.flash then flashUntil = GetTime() + 8 end
              end
            end
          end
        end
      end
    end
  end

  local driver = CreateFrame("Frame")
  driver:SetScript("OnUpdate", function()
    local now = GetTime()
    if now < flashUntil then
      btn:SetAlpha(0.55 + 0.45 * math.abs(math.sin(now * 5)))
    else
      btn:SetAlpha(1)
    end
    EpochNow()
    if cal and (now - cal.t0) > 1500 then CalFinish(false) end
    pollT = pollT + arg1
    if pollT >= (cal and 0.1 or 0.5) then
      pollT = 0
      Poll()
    end
    uiT = uiT + arg1
    if uiT >= 0.25 then
      uiT = 0
      ApplyVisibility()
      RunAlerts()
      if panel:IsShown() then Refresh() end
    end
  end)

  ApplyVisibility()

  ------------------------------------------------------------------------
  -- Slash commands
  ------------------------------------------------------------------------
  local function Words(msg)
    local t = {}
    for w in gfind(msg or "", "%S+") do table.insert(t, w) end
    return t
  end

  local function Toggle(name, key)
    CFG[key] = not CFG[key]
    Say(name .. " " .. (CFG[key] and "on" or "off") .. ".")
  end

  local function NthRoute(n)
    n = tonumber(n)
    if not n then return nil end
    local c = 0
    for i = 1, table.getn(ROUTES) do
      c = c + 1
      if c == n then return ROUTES[i] end
    end
    return nil
  end

  SlashCmdList["OCTOBUS"] = function(msg)
    msg = msg or ""
    local w = Words(msg)
    local cmd = string.lower(w[1] or "")

    if cmd == "" then
      ToggleShown()

    elseif cmd == "list" then
      for i = 1, table.getn(ROUTES) do
        local r = ROUTES[i]
        local a, _, _, b = RowText(r)
        Say(i .. ". " .. a .. "   " .. b .. "   (cycle " .. string.format("%.1f", Period(r)) .. "s)")
      end

    elseif cmd == "alert" then
      local s = tonumber(w[2])
      if s and s >= 0 then
        CFG.alert = s
        Say("alerts " .. (s == 0 and "off" or (s .. " seconds before arrival")) .. ".")
      else
        Say("usage: /ob alert <seconds>   (0 = off)")
      end

    elseif cmd == "sound" then Toggle("sound alert", "sound")
    elseif cmd == "chat"  then Toggle("chat alert", "chat")
    elseif cmd == "flash" then Toggle("minimap icon flash", "flash")
    elseif cmd == "zone"  then Toggle("auto-show limited to Orgrimmar/Durotar (off = always show)", "zoneOnly")
    elseif cmd == "where" then
      Say("zone: \"" .. (GetZoneText() or "") .. "\"  sub-zone: \"" .. (GetSubZoneText() or "") .. "\"  auto-shows here: " .. tostring(InOrg()))
    elseif cmd == "allow" then
      local nm = ""
      for i = 2, table.getn(w) do nm = nm .. (i > 2 and " " or "") .. w[i] end
      if nm == "" then
        Say("usage: /ob allow <zone or sub-zone name>   (see /ob where). Current extras: " .. table.concat(CFG.allow, ", "))
      else
        table.insert(CFG.allow, nm)
        Say("added \"" .. nm .. "\" to the places where the window opens by itself.")
      end
    elseif cmd == "allowclear" then
      CFG.allow = {}
      Say("extra places cleared (Orgrimmar and Durotar remain).")
    elseif cmd == "shape" then
      local v = string.lower(w[2] or "")
      if v == "square" or v == "round" then
        CFG.shape = v
      elseif v == "auto" then
        CFG.shape = nil
      else
        Say("usage: /ob shape square|round|auto   (now: " .. (CFG.shape or "auto") .. ", looks " .. (MinimapIsSquare() and "square" or "round") .. ")")
        return
      end
      PlaceButton()
      Say("minimap icon placement: " .. (CFG.shape or "auto") .. ".")
    elseif cmd == "boat"  then
      CFG.hideBoat = not CFG.hideBoat
      Say("Sparkwater Port boat " .. (CFG.hideBoat and "hidden" or "shown") .. ".")
    elseif cmd == "lock" then Toggle("window locked", "locked")
    elseif cmd == "resetpos" then
      CFG.pos = nil
      CFG.angle = nil
      PlaceButton()
      override = nil
      panel:Hide()
      ApplyVisibility()
      Say("window and minimap icon moved back to their default spots, auto mode restored.")

    elseif cmd == "name" then
      local r = NthRoute(w[2])
      local text = ""
      for i = 3, table.getn(w) do text = text .. (i > 3 and " " or "") .. w[i] end
      if r and text ~= "" then
        DB.names[r.entry] = text
        Say("route " .. w[2] .. " is now called: " .. text)
      else
        Say("usage: /ob name <number from /ob list> <new name>")
      end

    elseif cmd == "period" then
      local r = NthRoute(w[2])
      local s = tonumber(w[3])
      if r and s and s > 30 then
        DB.period[r.entry] = s
        Say(RouteName(r) .. ": cycle set to " .. s .. "s.")
      else
        Say("usage: /ob period <number from /ob list> <seconds>")
      end

    elseif cmd == "calibrate" or cmd == "cal" then
      if w[2] == "stop" or w[2] == "cancel" then
        if cal then CalFinish(false) else Say("not calibrating.") end
      elseif not dllOk then
        Say("calibration needs ZepSense.dll answering (see /ob debug).")
      else
        local n = CalStart()
        override = "show"
        ApplyVisibility()
        Say("calibrating " .. n .. " transports. Stand where you can see the docks (between the two towers), do not /reload, and wait.")
        Say("each transport needs " .. "1 fresh arrival (2 the first time). Rows turn + when done. /ob calibrate stop cancels.")
        local seen = 0
        for i = 1, table.getn(ROUTES) do
          if seenState[ROUTES[i].entry] then seen = seen + 1 end
        end
        if seen == 0 then
          Say("none of them are in view this second. That is normal: each transport is out of range for part of its trip. If the footer still says nothing has been seen after about 10 minutes, move closer to the towers.")
        end
      end

    elseif cmd == "reset" then
      DB.anchor = {}
      DB.period = {}
      DB.origin = {}
      DB.dwell = {}
      DB.lastCal = nil
      DB.lastObs = {}
      cal = nil
      confirmed = {}
      seenState = {}
      Say("learned data cleared; using built-in values until each zeppelin is seen again.")

    elseif cmd == "debug" then
      Say("DLL function present: " .. tostring(type(ZepTransports) == "function") ..
        ", answering: " .. tostring(dllOk))
      if type(ZepTransports) == "function" then
        local ok, str = pcall(ZepTransports)
        str = tostring(str)
        Say("raw (" .. string.len(str) .. " chars): " .. string.sub(str, 1, 180))
      end

    else
      Say("/ob (window on/off)  |  list  |  alert <s>  |  sound|chat|flash|zone|boat|lock  |  where  |  shape <square|round|auto>  |  allow <name>  |  resetpos  |  name <n> <text>  |  period <n> <s>  |  calibrate  |  reset  |  debug")
    end
  end

end)
if not OB_OK then
  OB_STAGE = "start-up error: " .. tostring(OB_ERR)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccOctoBus:|r |cffff5555" .. OB_STAGE .. "|r")
end

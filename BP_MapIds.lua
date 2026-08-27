-- BP_MapIds.lua
-- ---------------------------------------------------------------------------
-- Zonenname -> WorldMapArea-ID.
--
-- Carbonite kennt seine Zonen unter eigenen Indizes, das Servermodul braucht
-- die WoW-Karten-ID. Die Bruecke ist der lokalisierte Zonenname: einmal ueber
-- alle Kontinente und Zonen laufen und dabei GetCurrentMapAreaID() abfragen.
-- Keine eingebaute Tabelle, funktioniert deshalb in jeder Sprache.
-- ---------------------------------------------------------------------------

Botpad = Botpad or {}
local BP = Botpad

BP.MapIds = {}
local M = BP.MapIds

local byName, built = nil, false

local function norm(s)
   if type(s) ~= "string" then return nil end
   s = string.gsub(s, "^%s*(.-)%s*$", "%1")
   if s == "" then return nil end
   return string.lower(s)
end

function M.Build(force)
   if built and not force then return byName end
   byName = {}
   built = true

   if not GetMapContinents or not SetMapZoom or not GetCurrentMapAreaID then
      return byName
   end

   local prev = GetCurrentMapAreaID()
   local conts = { GetMapContinents() }

   for c = 1, #conts do
      SetMapZoom(c, 0)
      local cid, cn = GetCurrentMapAreaID(), norm(conts[c])
      if cn and cid and cid > 0 and not byName[cn] then byName[cn] = cid end

      local zones = { GetMapZones(c) }
      for z = 1, #zones do
         SetMapZoom(c, z)
         local id, zn = GetCurrentMapAreaID(), norm(zones[z])
         if zn and id and id > 0 and not byName[zn] then byName[zn] = id end
      end
   end

   if prev and prev > 0 and SetMapByID then pcall(SetMapByID, prev)
   elseif SetMapToCurrentZone then pcall(SetMapToCurrentZone) end

   return byName
end

function M.Resolve(name)
   if not name then return nil end
   M.Build()
   local key = norm(name)
   if not key then return nil end
   if byName[key] then return byName[key] end

   local base = string.match(key, "^([^%(]+)")
   if base then
      base = string.gsub(base, "%s+$", "")
      if byName[base] then return byName[base] end
   end
   return nil
end

-- Karten-ID und eigene normalisierte Position der aktuellen Zone.
-- Der Server prueft damit seine Zuordnung gegen die ihm bekannte echte
-- Position und erkennt eine falsche Karten-ID.
function M.SelfSample()
   local prev = GetCurrentMapAreaID and GetCurrentMapAreaID() or 0
   if SetMapToCurrentZone then pcall(SetMapToCurrentZone) end

   local id = GetCurrentMapAreaID and GetCurrentMapAreaID() or 0
   local px, py = GetPlayerMapPosition("player")

   if prev and prev > 0 and prev ~= id and SetMapByID then pcall(SetMapByID, prev) end

   if id and id > 0 and px and py and (px > 0 or py > 0) then return id, px, py end
   return 0, 0, 0
end

-- Normalisierte eigene Position auf einer BESTIMMTEN Karte.
-- Wichtig: pcall meldet auch dann Erfolg, wenn SetMapByID die Karte gar nicht
-- gewechselt hat. Ohne die Kontrolle liefert GetPlayerMapPosition die Position
-- auf der alten Karte, und der Server bekaeme eine Gegenprobe aus einer ganz
-- anderen Zone.
function M.Calibration(uiMapId)
   if not uiMapId or not GetPlayerMapPosition then return 0, 0, 0 end
   local prev = GetCurrentMapAreaID and GetCurrentMapAreaID() or 0
   local switched = false

   if prev ~= uiMapId and SetMapByID then
      if pcall(SetMapByID, uiMapId) then switched = true end
   end

   local shown = GetCurrentMapAreaID and GetCurrentMapAreaID() or 0
   local px, py = 0, 0
   if shown == uiMapId then px, py = GetPlayerMapPosition("player") end

   if switched then
      if prev and prev > 0 then pcall(SetMapByID, prev)
      elseif SetMapToCurrentZone then pcall(SetMapToCurrentZone) end
   end

   if px and py and (px > 0 or py > 0) then return 1, px, py end
   return 0, 0, 0
end

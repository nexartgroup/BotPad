-- BP_Carbonite.lua
-- ---------------------------------------------------------------------------
-- Liest das in Carbonite gesetzte Goto-Ziel.
--
-- Carbonite haelt seine Route in Kontinentkoordinaten. Gebraucht werden
-- normalisierte Zonenkoordinaten 0..1, weil nur die sich serverseitig per
-- WorldMapArea.dbc exakt in Weltkoordinaten umrechnen lassen. Carbonite
-- liefert die Umrechnung selbst mit:
--
--     map:GZP(mapIndex, kontinentX, kontinentY)  ->  zonenX, zonenY (0..100)
-- ---------------------------------------------------------------------------

Botpad = Botpad or {}
local BP = Botpad

BP.Carb = {}
local CB = BP.Carb

local function GetMap()
   if not Nx or not Nx.Map or not Nx.Map.GeM then return nil end
   local ok, map = pcall(function() return Nx.Map:GeM(1) end)
   if ok and type(map) == "table" then return map end
   return nil
end

function CB.IsAvailable()
   return GetMap() ~= nil
end

local function MapName(idx)
   if Nx and Nx.MITN and idx then return Nx.MITN[idx] end
   return nil
end

-- Letzter Punkt der Carbonite-Route = das eigentliche Ziel
function CB.GetTarget()
   local map = GetMap()
   if not map then return nil, "Carbonite ist nicht geladen." end

   local src = map.Tra1
   if not src or #src == 0 then src = map.Tar end
   if not src or #src == 0 then return nil, "Kein Carbonite-Ziel gesetzt." end

   local last
   for i = #src, 1, -1 do
      local e = src[i]
      if type(e.TMX) == "number" and type(e.TMY) == "number" then last = e break end
   end
   if not last then return nil, "Carbonite liefert keine Zielkoordinaten." end
   if not last.MaI then return nil, "Carbonite liefert keinen Kartenindex." end

   local ok, zx, zy = pcall(function() return map:GZP(last.MaI, last.TMX, last.TMY) end)
   if not ok or type(zx) ~= "number" or type(zy) ~= "number" then
      return nil, "Umrechnung in Zonenkoordinaten fehlgeschlagen."
   end
   if zx < -5 or zx > 105 or zy < -5 or zy > 105 then
      return nil, "Das Ziel liegt ausserhalb seiner eigenen Zone."
   end

   zx = math.max(0, math.min(100, zx))
   zy = math.max(0, math.min(100, zy))

   return {
      nx   = zx / 100,
      ny   = zy / 100,
      name = last.TaN1 or "Ziel",
      zone = MapName(last.MaI),
   }
end

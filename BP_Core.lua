-- BP_Core.lua
-- ---------------------------------------------------------------------------
-- Botpad -- minimales Bedienfeld.
--
--   * Teleport zum Carbonite-Ziel
--   * Playerbot-Selbstmodus an/aus
--   * Betriebsart waehlen
--
-- Der Teleport braucht das Servermodul mod-autotravel. Grund: die richtige
-- HOEHE laesst sich clientseitig nicht bestimmen. Lua kennt weder Terrain- noch
-- Kollisionsdaten, und ein Carbonite-Wegpunkt kommt von einer 2D-Karte. Das
-- Modul rechnet die Zonenkoordinaten per WorldMapArea.dbc in Weltkoordinaten
-- um und sucht die begehbare Flaeche dazu.
-- ---------------------------------------------------------------------------

Botpad = Botpad or {}
local BP = Botpad

BP.VERSION = "1.0"
local PREFIX = "|cff5ab0e8Botpad|r: "

local DEFAULTS = {
   Mode         = "normal",
   SelfCommand  = ".playerbot bot self",
   HideCommands = 1,
   ResetOnStop  = 1,
   ConfirmTp    = 1,
   MinimapAngle = 210,
   Shown        = 1,
   Debug        = 0,
}

function BP.Get(k)
   BotpadDB = BotpadDB or {}
   local v = BotpadDB[k]
   if v == nil then return DEFAULTS[k] end
   return v
end
function BP.Set(k, v) BotpadDB = BotpadDB or {} BotpadDB[k] = v end
function BP.GetBool(k) local v = BP.Get(k) return v == 1 or v == true end

function BP.Print(m) if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(m or "")) end end
function BP.Warn(m)  if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. "|cffff8800" .. tostring(m or "") .. "|r") end end
function BP.Debug(m) if BP.GetBool("Debug") then BP.Print("|cff888888" .. tostring(m or "") .. "|r") end end
function BP.trim(s) if not s then return "" end return (string.gsub(s, "^%s*(.-)%s*$", "%1")) end

-- ---------------------------------------------------------------------------
-- Teleport
-- ---------------------------------------------------------------------------

local function BuildArgs()
   if not BP.Carb.IsAvailable() then
      return nil, "Carbonite ist nicht geladen."
   end

   local t, err = BP.Carb.GetTarget()
   if not t then return nil, err end

   local uiMapId = BP.Get("ForcedMapId") or BP.MapIds.Resolve(t.zone)
   if not uiMapId then
      uiMapId = select(1, BP.MapIds.SelfSample())
      if not uiMapId or uiMapId == 0 then
         return nil, "Zone '" .. tostring(t.zone) .. "' liess sich keiner Karte zuordnen."
      end
      BP.Warn("Zone '" .. tostring(t.zone) .. "' unbekannt - benutze die aktuelle Karte.")
   end

   local hasCalib, pnx, pny = BP.MapIds.Calibration(uiMapId)
   local curMap, cnx, cny   = BP.MapIds.SelfSample()

   local name = string.gsub(t.name or "Ziel", "|", "")
   if string.len(name) > 40 then name = string.sub(name, 1, 40) end

   BP.Debug(string.format("Ziel %s | Karte %d | %.4f/%.4f | Kalib %d",
            name, uiMapId, t.nx, t.ny, hasCalib))

   return string.format("%d %.5f %.5f %d %.5f %.5f %d %.5f %.5f %s",
                        uiMapId, t.nx, t.ny, hasCalib, pnx, pny,
                        curMap, cnx, cny, name), name
end

local lastReply = 0

local function DoTeleport()
   local args, nameOrErr = BuildArgs()
   if not args then BP.Warn(nameOrErr) return end

   lastReply = 0
   BP.Bot.SendCommand(".at tp " .. args)

   -- Antwortet das Servermodul nicht, ist es nicht installiert.
   local started = GetTime()
   local w = CreateFrame("Frame")
   w:SetScript("OnUpdate", function()
      if lastReply > started then w:SetScript("OnUpdate", nil) return end
      if (GetTime() - started) < 5 then return end
      w:SetScript("OnUpdate", nil)
      BP.Warn("Keine Antwort vom Server. Ist mod-autotravel installiert und aktiv?")
   end)
end

function BP.Teleport()
   if not BP.GetBool("ConfirmTp") then DoTeleport() return end
   local args, nameOrErr = BuildArgs()
   if not args then BP.Warn(nameOrErr) return end
   StaticPopup_Show("BOTPAD_TP", nameOrErr)
end

StaticPopupDialogs["BOTPAD_TP"] = {
   text = "Zum Carbonite-Ziel teleportieren?\n\n|cffffffff%s|r",
   button1 = YES or "Ja",
   button2 = NO or "Nein",
   OnAccept = function() DoTeleport() end,
   timeout = 20,
   whileDead = false,
   hideOnEscape = true,
}

-- ---------------------------------------------------------------------------
-- Bot an / aus
-- ---------------------------------------------------------------------------

function BP.ToggleBot()
   -- Beim Ausschalten zuerst die Strategien zuruecksetzen, danach umschalten.
   if BP.Bot.running == true and BP.GetBool("ResetOnStop") then
      BP.Bot.ResetStrategies()
   end
   BP.Bot.Toggle()
end

-- ---------------------------------------------------------------------------
-- Chat
-- ---------------------------------------------------------------------------

local chat = CreateFrame("Frame", "BotpadChat")
chat:RegisterEvent("CHAT_MSG_SYSTEM")
chat:RegisterEvent("CHAT_MSG_WHISPER")
chat:RegisterEvent("ADDON_LOADED")
chat:RegisterEvent("PLAYER_LOGIN")

chat:SetScript("OnEvent", function(self, event, arg1)
   if event == "ADDON_LOADED" then
      if arg1 == "Botpad" then
         BotpadDB = BotpadDB or {}
         for k, v in pairs(DEFAULTS) do
            if BotpadDB[k] == nil then BotpadDB[k] = v end
         end
      end
      return
   end

   if event == "PLAYER_LOGIN" then
      if BP.UI then BP.UI.Build() end
      BP.Print("v" .. BP.VERSION .. " geladen. /botpad fuer Hilfe.")
      if not BP.Carb.IsAvailable() then
         BP.Warn("Carbonite nicht gefunden - der Teleport braucht es als Zielquelle.")
      end
      return
   end

   if type(arg1) ~= "string" then return end

   -- Antworten des Servermoduls
   if string.sub(arg1, 1, 4) == "[AT]" then
      lastReply = GetTime()
      local kind = string.sub(arg1, 5, 5)
      if kind == "M" then BP.Print(string.sub(arg1, 7)) end
      return
   end

   BP.Bot.OnSystemMessage(arg1)
end)

-- Eigene Botbefehle nicht im Chat anzeigen
local function Filter(a1, a2, a3)
   if not BP.GetBool("HideCommands") then return false end
   local msg
   if type(a1) == "string" then msg = a2 else msg = a3 end
   if BP.Bot.IsOwnCommand(msg) then return true end
   -- Protokollzeilen des Servermoduls ebenfalls verbergen
   if type(msg) == "string" and string.sub(msg, 1, 4) == "[AT]"
      and string.sub(msg, 5, 5) ~= "M" then
      return true
   end
   return false
end

if ChatFrame_AddMessageEventFilter then
   ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", Filter)
   ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", Filter)
   ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", Filter)
end

-- ---------------------------------------------------------------------------
-- Slash
-- ---------------------------------------------------------------------------

SLASH_BOTPAD1 = "/botpad"
SLASH_BOTPAD2 = "/bp"

SlashCmdList["BOTPAD"] = function(input)
   input = string.lower(BP.trim(input or ""))
   local cmd, rest = string.match(input, "^(%S*)%s*(.*)$")

   if cmd == "" then
      if BP.UI then BP.UI.Toggle() end

   elseif cmd == "tp" or cmd == "teleport" then
      BP.Teleport()

   elseif cmd == "bot" then
      BP.ToggleBot()

   elseif cmd == "modus" or cmd == "mode" then
      if rest == "" then
         BP.Print("Modi:")
         for _, m in ipairs(BP.Bot.Modes) do
            DEFAULT_CHAT_FRAME:AddMessage(string.format("   %s%-9s|r %s",
               (m.key == BP.Get("Mode")) and "|cff53d17a" or "|cffaaaaaa", m.name, m.desc))
         end
      else
         local found
         for _, m in ipairs(BP.Bot.Modes) do
            if m.key == rest or string.lower(m.name) == rest then found = m end
         end
         if found then BP.Bot.SetMode(found.key) else BP.Warn("Unbekannter Modus.") end
      end

   elseif cmd == "befehl" then
      if rest ~= "" then
         BP.Set("SelfCommand", rest)
         BP.Print("Umschaltbefehl: " .. rest)
      else
         BP.Print("Aktuell: " .. tostring(BP.Get("SelfCommand")))
      end

   elseif cmd == "karte" then
      local id = tonumber(rest)
      if id and id > 0 then BP.Set("ForcedMapId", id) BP.Print("Karten-ID erzwungen: " .. id)
      else BP.Set("ForcedMapId", nil) BP.Print("Karten-ID wieder automatisch.") end

   elseif cmd == "nachfrage" then
      BP.Set("ConfirmTp", BP.GetBool("ConfirmTp") and 0 or 1)
      BP.Print("Sicherheitsabfrage " .. (BP.GetBool("ConfirmTp") and "AN" or "AUS"))

   elseif cmd == "debug" then
      BP.Set("Debug", BP.GetBool("Debug") and 0 or 1)
      BP.Print("Debug " .. (BP.GetBool("Debug") and "AN" or "AUS"))

   else
      BP.Print("Befehle:")
      local l = {
         "/bp                Fenster ein/aus",
         "/bp tp             zum Carbonite-Ziel teleportieren",
         "/bp bot            Selbstmodus umschalten",
         "/bp modus [name]   minimal | normal | grind",
         "/bp befehl <text>  Umschaltbefehl anpassen",
         "/bp karte <id>     Karten-ID erzwingen (0 = automatisch)",
         "/bp nachfrage      Sicherheitsabfrage vor Teleport",
         "/bp debug          gesendete Befehle anzeigen",
      }
      for _, x in ipairs(l) do DEFAULT_CHAT_FRAME:AddMessage("   " .. x) end
   end
end

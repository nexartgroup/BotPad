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

BP.VERSION = "1.1"
local PREFIX = "|cff5ab0e8Botpad|r: "

local DEFAULTS = {
   Mode         = "normal",
   -- mod-playerbots registriert "playerbots" (Mehrzahl). AzerothCore erkennt nur
   -- den vollen Namen -- ".playerbot" ist ein unbekannter Befehl ("Es gibt keinen
   -- solchen Befehl", bei AllowPlayerCommands = 0 sogar Text in /sagen). Der
   -- Befehl ist ein Umschalter.
   SelfCommand  = ".playerbots bot self",
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

-- ---------------------------------------------------------------------------
-- Handschlag mit dem Servermodul
-- ---------------------------------------------------------------------------
--
-- ".at tp" geht erst hinaus, wenn das Modul sich gemeldet hat. Ohne das Modul
-- antwortet AzerothCore mit "Es gibt keinen solchen Befehl"; auf Servern mit
-- AllowPlayerCommands = 0 (nicht Standard) behandelt der Core den Befehl sogar als
-- gewoehnlichen Text (ChatHandler::_ParseCommands), und der Charakter riefe die
-- Koordinaten in /sagen. Fruehere Fassungen sendeten den Befehl blind und warnten
-- erst fuenf Sekunden spaeter. Der Handschlag liefert ausserdem die
-- Berechtigungen dieses Spielers.
--
-- Antwort: [AT]H|<version>|<aktiv>|<knoten>|<flug>|<afk>|<protokoll>|<rechte>|<faehigkeiten>
-- Faehigkeit 8 = ".at tp" ist fuer diesen Spieler erlaubt.

BP.srv = { state = "UNKNOWN", version = "?", proto = 0, sec = 0, caps = 0, capsKnown = false }

local CAP_TELEPORT = 8
local HELLO_TIMEOUT = 5
local pendingTp = nil       -- { args, name, at } wartet auf die Antwort

local function TeleportAllowed()
   if not BP.srv.capsKnown then return true end      -- aelteres Modul: der Server entscheidet
   return (math.floor(BP.srv.caps / CAP_TELEPORT) % 2) == 1
end

-- Ein einziger Beobachter fuer beide Fristen (Antwort auf den Teleport, Antwort auf
-- den Handschlag). Frueher entstand je Aufruf ein neuer Rahmen, und Rahmen werden
-- in WoW nie freigegeben.
local replyWatchFrom = nil
local watchFrame = CreateFrame("Frame", "BotpadWatch")
watchFrame:SetScript("OnUpdate", function()
   local now = GetTime()

   if replyWatchFrom then
      if lastReply > replyWatchFrom then
         replyWatchFrom = nil
      elseif (now - replyWatchFrom) >= 5 then
         replyWatchFrom = nil
         BP.Warn("Keine Antwort vom Server auf den Teleport. Ist mod-autotravel aktiv?")
      end
   end

   if pendingTp and (now - pendingTp.at) >= HELLO_TIMEOUT then
      pendingTp = nil
      BP.srv.state = "UNKNOWN"          -- naechster Versuch fragt erneut
      BP.Warn("Keine Antwort von mod-autotravel. Der Teleportbefehl wurde NICHT gesendet. " ..
              "Ist das Modul auf dem Server aktiv?")
   end
end)

local function SendTeleport(args)
   if not TeleportAllowed() then
      BP.Warn("Der Teleport ist dir auf diesem Server nicht erlaubt (Stufe " ..
              tostring(BP.srv.sec) .. "). Ein Spielleiter kann ihn mit " ..
              "AutoTravel.TeleportSecurity freigeben.")
      return
   end

   lastReply = 0
   BP.Bot.SendCommand(".at tp " .. args)

   -- Antwortet das Servermodul nach dem Handschlag trotzdem nicht, ist etwas faul.
   replyWatchFrom = GetTime()
end

local function OnHello(body)
   local ver, enabled, _, _, _, proto, sec, caps = strsplit("|", body)
   local s = BP.srv
   s.version   = ver or "?"
   s.proto     = tonumber(proto) or 3
   s.sec       = tonumber(sec) or 0
   s.capsKnown = (caps ~= nil and caps ~= "")
   s.caps      = tonumber(caps) or 0

   if (tonumber(enabled) or 1) == 0 then
      s.state = "DISABLED"
      pendingTp = nil
      BP.Warn("mod-autotravel ist auf diesem Server abgeschaltet.")
      return
   end

   s.state = "READY"
   if pendingTp then
      local p = pendingTp
      pendingTp = nil
      SendTeleport(p.args)
   end
end

-- Handschlag anstossen und den Teleport nach der Antwort ausfuehren.
local function HelloThenTeleport(args, name)
   pendingTp = { args = args, name = name, at = GetTime() }
   BP.srv.state = "HELLO"
   BP.Bot.SendCommand(".at hello")
end

local function DoTeleport()
   local args, nameOrErr = BuildArgs()
   if not args then BP.Warn(nameOrErr) return end

   local state = BP.srv.state
   if state == "READY" then
      SendTeleport(args)
   elseif state == "DISABLED" then
      BP.Warn("mod-autotravel ist auf diesem Server abgeschaltet.")
   elseif state == "HELLO" then
      pendingTp = pendingTp or { args = args, name = nameOrErr, at = GetTime() }
      pendingTp.args = args
   else
      HelloThenTeleport(args, nameOrErr)
   end
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
   -- Die Strategien beim Ausschalten zuruecksetzen erledigt Bot.Toggle().
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

chat:SetScript("OnEvent", function(self, event, arg1, arg2)
   if event == "ADDON_LOADED" then
      -- Der Name ist der Ordnername; die Anleitung nennt "BotPad", die TOC-Datei
      -- heisst "Botpad". Ein Vergleich mit genau einer Schreibweise liesse die
      -- Voreinstellungen und die Umstellung je nach Ordnername aus.
      if type(arg1) == "string" and string.lower(arg1) == "botpad" then
         BotpadDB = BotpadDB or {}
         for k, v in pairs(DEFAULTS) do
            if BotpadDB[k] == nil then BotpadDB[k] = v end
         end
         -- Der frueher mitgelieferte Standardbefehl war ein unbekannter Befehl.
         -- Hat der Spieler ihn nie angefasst, auf den richtigen umstellen.
         if BotpadDB.SelfCommand == ".playerbot bot self" then
            BotpadDB.SelfCommand = DEFAULTS.SelfCommand
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
      -- Zwei Addons, die beide den Selbstmodus konfigurieren, wuerden dem Bot
      -- bei jedem Einschalten zwei verschiedene Strategiesaetze schicken.
      if IsAddOnLoaded and IsAddOnLoaded("AutoTravel") then
         BP.Bot.disabled = true
         BP.Warn("AutoTravel ist ebenfalls geladen und steuert den Playerbot. Botpad setzt " ..
                 "deshalb keine Strategien; Teleport und Umschalter bleiben nutzbar.")
      end
      return
   end

   if type(arg1) ~= "string" then return end

   -- Fluesternachrichten zaehlen nur vom eigenen Charakter. Jeder andere Spieler
   -- koennte sonst "SelfBot is now active." fluestern und den Zustand im Addon
   -- verfaelschen (oder eine [AT]-Zeile vortaeuschen).
   if event == "CHAT_MSG_WHISPER" and arg2 ~= UnitName("player") then return end

   -- Antworten des Servermoduls
   if string.sub(arg1, 1, 4) == "[AT]" then
      lastReply = GetTime()
      local kind = string.sub(arg1, 5, 5)
      local body = string.sub(arg1, 7)
      if kind == "M" then BP.Print(body)
      elseif kind == "H" then OnHello(body) end
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

   elseif cmd == "info" then
      local s = BP.srv
      BP.Print("Botpad " .. BP.VERSION)
      BP.Print("Servermodul: " .. s.state ..
               (s.state == "READY" and (" (Version " .. s.version .. ", Stufe " .. s.sec ..
                                        ", Teleport " .. (TeleportAllowed() and "erlaubt" or "nicht erlaubt") .. ")") or ""))
      BP.Print("Selbstmodus: " .. BP.Bot.StatusText() .. "  |  Befehl: " .. tostring(BP.Get("SelfCommand")))
      BP.Print("Carbonite: " .. (BP.Carb.IsAvailable() and "gefunden" or "nicht gefunden"))

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
         "/bp info           Version, Verbindung, Berechtigung",
         "/bp debug          gesendete Befehle anzeigen",
      }
      for _, x in ipairs(l) do DEFAULT_CHAT_FRAME:AddMessage("   " .. x) end
   end
end

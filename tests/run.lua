-- tests/run.lua
-- ---------------------------------------------------------------------------
--     lua5.1 tests/run.lua          (im Hauptverzeichnis des Addons)
--
-- Laedt Botpad in die WoW-Attrappe aus mock_wow.lua und prueft, was sich ohne
-- Spiel pruefen laesst: Handschlag vor dem Teleport, Erkennung der Meldungen von
-- mod-playerbots, Umschalter, Auswahlfeld, Zusammenspiel mit AutoTravel.
-- ---------------------------------------------------------------------------

package.path = "./tests/?.lua;" .. package.path
local W = require("mock_wow")

local passes, failures = 0, 0
local current = ""

local function check(cond, msg)
   if cond then passes = passes + 1
   else failures = failures + 1 print("  FEHLER [" .. current .. "] " .. tostring(msg)) end
end
local function eq(a, b, msg)
   check(a == b, tostring(msg) .. "  (erwartet " .. tostring(b) .. ", war " .. tostring(a) .. ")")
end

local function boot(addonLoaded)
   W.Install()
   _G.IsAddOnLoaded = addonLoaded or function() return false end
   _G.BotpadDB = nil
   W.LoadToc(".", "Botpad.toc")
   W.Fire("ADDON_LOADED", "Botpad")
   W.Fire("PLAYER_LOGIN")
end

local function count(prefix)
   local n = 0
   for _, c in ipairs(W.SentCommands()) do
      if c:sub(1, #prefix) == prefix then n = n + 1 end
   end
   return n
end

local function warned(text)
   for _, m in ipairs(W.messages) do if m:find(text, 1, true) then return true end end
   return false
end

local function test(name, fn)
   current = name
   io.write("- " .. name .. "\n")
   local ok, err = xpcall(fn, debug.traceback)
   if not ok then failures = failures + 1 print("  ABSTURZ [" .. name .. "] " .. tostring(err)) end
end

-- Carbonite-Attrappe wie in den AutoTravel-Tests
local function installCarbonite()
   local current = 0
   _G.GetMapContinents = function() return "Oestliche Koenigreiche" end
   _G.GetMapZones = function() return "Elwynn" end
   _G.SetMapZoom = function(_, z) current = (z == 0) and 14 or 12 end
   _G.GetCurrentMapAreaID = function() return current end
   _G.SetMapByID = function(id) current = id end
   _G.SetMapToCurrentZone = function() current = 12 end
   _G.GetPlayerMapPosition = function() return 0.40, 0.60 end
   _G.Nx = {
      Map = { GeM = function()
         return { Tra1 = { { TMX = 1, TMY = 2, MaI = 1, TaN1 = "Ziel |cffff0000rot|r" } },
                  GZP = function() return 50, 50 end }
      end },
      MITN = { "Elwynn" },
   }
end

local function hello(caps, sec)
   W.ServerLine(string.format("[AT]H|4.0|1|250|1|1|4|%d|%d", sec or 0, caps or 63))
end

-- ---------------------------------------------------------------------------

test("Dateien laden und Oberflaeche bauen ohne Fehler", function()
   boot()
   check(Botpad ~= nil and Botpad.UI and Botpad.Bot and Botpad.Carb, "Module vorhanden")
   check(_G.BotpadPanel ~= nil, "Panel gebaut")
end)

test("Standardbefehl ist 'playerbots' (Mehrzahl), der alte unbekannte Befehl wird umgestellt", function()
   boot()
   eq(BotpadDB.SelfCommand, ".playerbots bot self", "Standard")

   W.Install()
   _G.IsAddOnLoaded = function() return false end
   _G.BotpadDB = { SelfCommand = ".playerbot bot self" }
   W.LoadToc(".", "Botpad.toc")
   W.Fire("ADDON_LOADED", "Botpad")
   eq(BotpadDB.SelfCommand, ".playerbots bot self", "alter Standard ersetzt")

   W.Install()
   _G.IsAddOnLoaded = function() return false end
   _G.BotpadDB = { SelfCommand = ".mein befehl" }
   W.LoadToc(".", "Botpad.toc")
   W.Fire("ADDON_LOADED", "Botpad")
   eq(BotpadDB.SelfCommand, ".mein befehl", "eigene Eingabe bleibt")
end)

-- ---------------------------------------------------------------------------
-- Teleport
-- ---------------------------------------------------------------------------

test("Teleport: erst der Handschlag, der Befehl erst nach der Antwort", function()
   boot()
   installCarbonite()
   BotpadDB.ConfirmTp = 0
   Botpad.Teleport()
   W.Advance(1)
   eq(count(".at hello"), 1, "Handschlag gesendet")
   eq(count(".at tp"), 0, "noch kein Teleportbefehl (er landete sonst in /sagen)")
   hello(63, 2)
   W.Advance(1)
   eq(count(".at tp"), 1, "Teleport nach der Antwort")
   local tp
   for _, c in ipairs(W.SentCommands()) do if c:sub(1, 7) == ".at tp " then tp = c end end
   check(tp and not tp:find("|", 1, true), "kein '|' im Befehl")
end)

test("Teleport: ohne Antwort wird der Befehl NICHT gesendet", function()
   boot()
   installCarbonite()
   BotpadDB.ConfirmTp = 0
   Botpad.Teleport()
   W.Advance(6)
   eq(count(".at tp"), 0, "kein Teleportbefehl ohne Modul")
   check(warned("NICHT gesendet"), "Spieler wird gewarnt")
   -- der naechste Versuch fragt erneut
   W.ClearSent()
   Botpad.Teleport()
   W.Advance(1)
   eq(count(".at hello"), 1, "erneuter Handschlag")
end)

test("Teleport: ohne Berechtigung wird nichts gesendet und der Grund genannt", function()
   boot()
   installCarbonite()
   BotpadDB.ConfirmTp = 0
   Botpad.Teleport()
   W.Advance(0.5)
   hello(39, 0)                        -- kein Teleport (8) in den Faehigkeiten
   W.Advance(1)
   eq(count(".at tp"), 0, "kein Befehl")
   check(warned("nicht erlaubt"), "Grund genannt")
end)

test("Teleport: nach READY geht jeder weitere Teleport direkt hinaus", function()
   boot()
   installCarbonite()
   BotpadDB.ConfirmTp = 0
   Botpad.Teleport()
   W.Advance(0.5)
   hello(63, 2)
   W.Advance(1)
   W.ClearSent()
   Botpad.Teleport()
   W.Advance(1)
   eq(count(".at hello"), 0, "kein zweiter Handschlag")
   eq(count(".at tp"), 1, "Teleport direkt")
end)

test("Teleport: serverseitig abgeschaltetes Modul wird erkannt", function()
   boot()
   installCarbonite()
   BotpadDB.ConfirmTp = 0
   Botpad.Teleport()
   W.Advance(0.5)
   W.ServerLine("[AT]H|4.0|0|0|0|0|4|0|0")
   W.Advance(1)
   eq(count(".at tp"), 0, "kein Befehl")
   check(warned("abgeschaltet"), "Hinweis")
end)

test("Teleport: Abfrage mit Namen ohne Farbcodes", function()
   boot()
   installCarbonite()
   Botpad.Teleport()
   check(W.popup ~= nil and W.popup.which == "BOTPAD_TP", "Abfrage geoeffnet")
   check(W.popup and not W.popup.text:find("|", 1, true), "Name ohne Farbcodes: " .. tostring(W.popup and W.popup.text))
end)

-- ---------------------------------------------------------------------------
-- Selbstmodus
-- ---------------------------------------------------------------------------

test("aktuelle und aeltere Bestaetigungstexte werden erkannt", function()
   boot()
   local B = Botpad.Bot
   W.ServerLine("SelfBot is now active.")
   eq(B.running, true, "aktueller Text: an")
   W.ServerLine("SelfBot is now deactivated.")
   eq(B.running, false, "aktueller Text: aus")
   W.ServerLine("Enable player botAI")
   eq(B.running, true, "alter Text: an")
   W.ServerLine("Disable player botAI")
   eq(B.running, false, "alter Text: aus")
end)

test("Einschalten wendet den Modus an (drei Strategiebefehle nach dem Reset)", function()
   boot()
   W.ServerLine("SelfBot is now active.")
   W.Advance(5)
   local whispers = 0
   for _, s in ipairs(W.sent) do if s.channel == "WHISPER" then whispers = whispers + 1 end end
   eq(whispers, 6, "3 Reset + nc, co, ll")
   for _, x in ipairs(W.sent) do
      check(not (x.text or ""):match("^ss "), "kein 'ss' (Sicherheitsabstand ist kein Teil der Modi)")
   end
end)

test("alle Modi: ll kennt nur normal/all, nc/co ohne Leerbefehle", function()
   boot()
   for _, m in ipairs(Botpad.Bot.Modes) do
      check(m.ll == "normal" or m.ll == "all", "ll-Wert gueltig: " .. m.key)
      check(m.nc ~= "" and m.co ~= "", "nc/co gesetzt: " .. m.key)
      check(m.ss == nil, "kein ss: " .. m.key)
   end
end)

test("weitere Verweigerungstexte werden erkannt", function()
   for _, text in ipairs({ "SelfBot is restricted for this account.",
                           "Playerbot system is currently disabled!",
                           "You cannot control bots yet" }) do
      boot()
      Botpad.Bot.ApplyMode(true)
      W.ServerLine(text)
      W.Advance(5)
      local whispers = 0
      for _, s in ipairs(W.sent) do if s.channel == "WHISPER" then whispers = whispers + 1 end end
      eq(whispers, 0, "Warteschlange geleert: " .. text)
      eq(Botpad.Bot.running, false, "als aus gewertet: " .. text)
   end
end)

test("Umschalter bei unbekanntem Zustand: Gegenteil bestaetigt -> einmal erneut umschalten", function()
   boot()
   local B = Botpad.Bot
   Botpad.ToggleBot()                       -- Zustand unbekannt: gewuenscht ist "an"
   W.Advance(1)
   eq(count(".playerbots bot self"), 1, "erster Umschalter")
   W.ServerLine("SelfBot is now deactivated.")   -- war in Wahrheit schon an
   W.Advance(1)
   eq(count(".playerbots bot self"), 2, "ein zweiter Umschalter")
   W.ServerLine("SelfBot is now active.")
   W.Advance(5)
   eq(B.running, true, "Endzustand an")
   eq(count(".playerbots bot self"), 2, "nicht noch ein dritter")
   local whispers = 0
   for _, s in ipairs(W.sent) do if s.channel == "WHISPER" then whispers = whispers + 1 end end
   eq(whispers, 6, "Modus genau einmal angewandt (3 Reset + 3 Strategien)")
end)

test("Umschalter: zweite Abweichung gibt auf und meldet, statt zu pendeln", function()
   boot()
   Botpad.ToggleBot()
   W.Advance(1)
   W.ServerLine("SelfBot is now deactivated.")
   W.Advance(1)
   W.ServerLine("SelfBot is now deactivated.")
   W.Advance(2)
   eq(count(".playerbots bot self"), 2, "es bleibt bei einem Wiederholungsversuch")
   check(warned("nicht in den gewuenschten Zustand"), "Spieler informiert")
end)

test("Fluestern anderer Spieler kann den Zustand nicht verfaelschen", function()
   boot()
   local B = Botpad.Bot
   W.Fire("CHAT_MSG_WHISPER", "SelfBot is now active.", "Fremder")
   eq(B.running, nil, "fremdes Fluestern ignoriert")
   W.Fire("CHAT_MSG_WHISPER", "SelfBot is now active.", UnitName("player"))
   eq(B.running, true, "eigenes Fluestern zaehlt")
end)

test("ADDON_LOADED: Ordnername in beliebiger Schreibweise", function()
   for _, name in ipairs({ "Botpad", "BotPad", "BOTPAD" }) do
      W.Install()
      _G.IsAddOnLoaded = function() return false end
      _G.BotpadDB = nil
      W.LoadToc(".", "Botpad.toc")
      W.Fire("ADDON_LOADED", name)
      check(BotpadDB ~= nil and BotpadDB.SelfCommand == ".playerbots bot self", "Voreinstellungen fuer " .. name)
   end
end)

test("Verweigerung durch den Server: erklaert, Warteschlange geleert", function()
   boot()
   Botpad.Bot.ApplyMode(true)           -- Strategiebefehle stehen in der Warteschlange
   W.ServerLine("SelfBot is disabled server-wide.")
   W.Advance(5)
   local whispers = 0
   for _, s in ipairs(W.sent) do if s.channel == "WHISPER" then whispers = whispers + 1 end end
   eq(whispers, 0, "Fluesterbefehle verworfen")
   check(warned("verweigert"), "Spieler informiert")
   eq(Botpad.Bot.running, false, "als aus gewertet")
end)

test("Ausschalten: einmal zuruecksetzen, dann umschalten (frueher zehn Nachrichten)", function()
   boot()
   W.ServerLine("SelfBot is now active.")
   W.Advance(5)
   W.ClearSent()
   Botpad.ToggleBot()
   W.Advance(5)
   local whispers, cmds = 0, 0
   for _, s in ipairs(W.sent) do
      if s.channel == "WHISPER" then whispers = whispers + 1 end
      if s.text == ".playerbots bot self" then cmds = cmds + 1 end
   end
   eq(whispers, 3, "genau ein Reset (3 Fluesterbefehle)")
   eq(cmds, 1, "ein Umschalter")
   -- Reihenfolge: Reset vor dem Umschalter
   local iCmd, iLastWhisper = 0, 0
   for i, s in ipairs(W.sent) do
      if s.text == ".playerbots bot self" then iCmd = i end
      if s.channel == "WHISPER" then iLastWhisper = i end
   end
   check(iLastWhisper < iCmd, "Reset kommt vor dem Umschalter")
end)

test("Einschalten aus dem Zustand 'aus': nur der Umschalter, kein Reset", function()
   boot()
   W.ServerLine("SelfBot is now deactivated.")
   W.ClearSent()
   Botpad.ToggleBot()
   W.Advance(3)
   eq(#W.sent, 1, "nur ein Befehl")
end)

test("ResetOnStop aus: kein Reset beim Ausschalten", function()
   boot()
   BotpadDB.ResetOnStop = 0
   W.ServerLine("SelfBot is now active.")
   W.Advance(5)
   W.ClearSent()
   Botpad.ToggleBot()
   W.Advance(3)
   eq(#W.sent, 1, "nur der Umschalter")
end)

-- ---------------------------------------------------------------------------
-- Oberflaeche
-- ---------------------------------------------------------------------------

test("Regression: das Auswahlfeld zeigt nach einem Moduswechsel den neuen Modus", function()
   boot()
   Botpad.Bot.SetMode("minimal")
   eq(_G.BotpadModeDropDownText:GetText(), "Minimal", "Text des Auswahlfeldes")
   Botpad.Bot.SetMode("grind")
   eq(_G.BotpadModeDropDownText:GetText(), "Grind", "und noch einmal")
end)

test("Oberflaeche bleibt in allen Zustaenden fehlerfrei", function()
   boot()
   for _, v in ipairs({ true, false }) do
      Botpad.Bot.running = v
      Botpad.UI.Update()
   end
   Botpad.Bot.running = nil
   Botpad.UI.Update()
   check(true, "kein Fehler")
end)

-- ---------------------------------------------------------------------------
-- Zusammenspiel mit AutoTravel
-- ---------------------------------------------------------------------------

test("ist AutoTravel geladen, setzt Botpad keine Strategien (kein doppelter Satz)", function()
   boot(function(name) return name == "AutoTravel" end)
   check(Botpad.Bot.disabled, "Strategiesteuerung abgeschaltet")
   check(warned("AutoTravel ist ebenfalls geladen"), "Hinweis ausgegeben")
   W.ServerLine("SelfBot is now active.")
   W.Advance(5)
   local whispers = 0
   for _, s in ipairs(W.sent) do if s.channel == "WHISPER" then whispers = whispers + 1 end end
   eq(whispers, 0, "keine Strategiebefehle")
   eq(Botpad.Bot.running, true, "Zustand wird trotzdem erkannt")
end)

-- ---------------------------------------------------------------------------
-- Chat
-- ---------------------------------------------------------------------------

test("Protokollzeilen: Handschlag verborgen, Meldungen sichtbar", function()
   boot()
   check(W.Filtered("CHAT_MSG_SYSTEM", "[AT]H|4.0|1|0|0|0|4|0|63"), "Handschlag verborgen")
   check(W.Filtered("CHAT_MSG_SYSTEM", "[AT]S|IDLE|0|-|0|0|0|0|0|0"), "Status verborgen")
   check(W.Filtered("CHAT_MSG_SYSTEM", "[AT]M|Teleport zu Ziel") == false, "Meldung bleibt sichtbar")
   check(W.Filtered("CHAT_MSG_SYSTEM", "Willkommen") == false, "normale Zeile bleibt")
end)

test("alle Slash-Befehle laufen fehlerfrei", function()
   boot()
   installCarbonite()
   for _, cmd in ipairs({ "", "info", "modus", "modus minimal", "modus unbekannt", "befehl", "befehl .x y",
                          "karte 12", "karte 0", "nachfrage", "debug", "hilfe", "bot", "tp" }) do
      local ok, err = pcall(SlashCmdList["BOTPAD"], cmd)
      check(ok, "/bp " .. cmd .. " -> " .. tostring(err))
   end
end)

print(string.format("\n%d Pruefungen, %d Fehler", passes, failures))
os.exit(failures == 0 and 0 or 1)

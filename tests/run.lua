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

-- Was an InterfaceOptions_AddCategory / ..._OpenToCategory ging
local added, opened = {}, {}

local function boot(addonLoaded, savedVars)
   W.Install()
   added, opened = {}, {}
   _G.InterfaceOptions_AddCategory = function(f) added[#added + 1] = f end
   _G.InterfaceOptionsFrame_OpenToCategory = function(f) opened[#opened + 1] = f end
   _G.IsAddOnLoaded = addonLoaded or function() return false end
   _G.BotpadDB = savedVars
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

test("ist AutoTravel geladen, meldet Botpad das abgeschaltete Modul nur auf eigene Frage", function()
   boot(function(name) return name == "AutoTravel" end)
   installCarbonite()
   BotpadDB.ConfirmTp = 0
   -- Antwort auf den Handschlag von AutoTravel: das meldet AutoTravel selbst
   W.messages = {}
   W.ServerLine("[AT]H|4.0.5|0|0|0|0|4|0|0")
   check(not warned("abgeschaltet"), "ungefragt: keine zweite Warnung")
   -- Botpad hat selbst gefragt: dann kommt die Warnung
   W.messages = {}
   Botpad.Teleport()
   W.Advance(0.5)
   W.ServerLine("[AT]H|4.0.5|0|0|0|0|4|0|0")
   check(warned("abgeschaltet"), "auf eigene Frage: Warnung")
end)

test("ist AutoTravel geladen, meldet Botpad die Verweigerung nur nach eigenem Umschalten", function()
   boot(function(name) return name == "AutoTravel" end)
   W.messages = {}
   W.ServerLine("SelfBot is disabled server-wide.")
   check(not warned("verweigert"), "fremdes Umschalten: keine zweite Meldung")
   W.messages = {}
   Botpad.Bot.Toggle()
   W.ServerLine("SelfBot is disabled server-wide.")
   check(warned("verweigert"), "eigenes Umschalten: Meldung")
end)

test("ist AutoTravel geladen, setzt Botpad beim Ausschalten keine Strategien zurueck", function()
   boot(function(name) return name == "AutoTravel" end)
   W.ServerLine("SelfBot is now active.")
   W.Advance(5)
   W.ClearSent()
   Botpad.Bot.Toggle()
   W.Advance(5)
   local whispers = 0
   for _, s in ipairs(W.sent) do if s.channel == "WHISPER" then whispers = whispers + 1 end end
   eq(whispers, 0, "kein nc !/co !/ll normal")
   eq(count(".playerbots bot self"), 1, "der Umschaltbefehl geht trotzdem hinaus")
end)

-- ---------------------------------------------------------------------------
-- Chat
-- ---------------------------------------------------------------------------

test("Protokollzeilen: alle verborgen, die Meldungen gibt Botpad selbst aus", function()
   boot()
   check(W.Filtered("CHAT_MSG_SYSTEM", "[AT]H|4.0|1|0|0|0|4|0|63"), "Handschlag verborgen")
   check(W.Filtered("CHAT_MSG_SYSTEM", "[AT]S|IDLE|0|-|0|0|0|0|0|0"), "Status verborgen")
   check(W.Filtered("CHAT_MSG_SYSTEM", "[AT]M|Teleport zu Ziel"), "die rohe Meldung wird verborgen ...")
   W.Fire("CHAT_MSG_SYSTEM", "[AT]M|Teleport zu Ziel")
   check(warned("Botpad|r: Teleport zu Ziel"), "... und mit dem Vorsatz ausgegeben")
   check(W.Filtered("CHAT_MSG_SYSTEM", "Willkommen") == false, "normale Zeile bleibt")

   -- ausgeschaltet: nichts wird verborgen
   BotpadDB.HideCommands = 0
   check(W.Filtered("CHAT_MSG_SYSTEM", "[AT]M|Teleport zu Ziel") == false, "HideCommands aus: alles sichtbar")
end)

test("alle Slash-Befehle laufen fehlerfrei", function()
   boot()
   installCarbonite()
   for _, cmd in ipairs({ "", "info", "modus", "modus minimal", "modus unbekannt", "befehl", "befehl .x y",
                          "karte 12", "karte 0", "nachfrage", "debug", "hilfe", "bot", "tp", "optionen",
                          "options", "einstellungen", "standard", "reset", "befehl ohnepunkt" }) do
      local ok, err = pcall(SlashCmdList["BOTPAD"], cmd)
      check(ok, "/bp " .. cmd .. " -> " .. tostring(err))
   end
end)


-- ---------------------------------------------------------------------------
-- Einstellungsseite
-- ---------------------------------------------------------------------------

local function optCheck(key)
   for i = 1, 40 do
      local cb = _G["BotpadOptCheck" .. i]
      if not cb then return nil end
      if cb.key == key then return cb end
   end
end

local function click(cb)
   cb:SetChecked(not cb:GetChecked())            -- der Client schaltet vor dem Skript um
   cb.__scripts.OnClick(cb)
end

local function optEdit(i) return _G["BotpadOptEdit" .. i] end
local function enter(eb, text)
   eb:SetText(text)
   eb.__scripts.OnEnterPressed(eb)
end

local function modeButton(key)
   for _, f in ipairs(W.frames) do
      if f.modeKey == key then return f end
   end
end

local function optionsButton(label)
   for _, f in ipairs(W.frames) do
      if f.label and f.label.GetText and f.label:GetText() == label and f.__scripts.OnClick then return f end
   end
end

test("die Einstellungsseite erscheint unter Interface -> AddOns -> Botpad", function()
   boot()
   eq(#added, 1, "eine Seite registriert")
   check(added[1] == _G.BotpadOptionsPanel, "die Seite")
   eq(added[1].name, "Botpad", "Name in der Liste")
   check(_G.BotpadOptionsScroll ~= nil, "in einem ScrollFrame")
   check(Botpad.Options and Botpad.Options.Open, "Open vorhanden")
   eq(Botpad.VERSION, "1.2", "Version")
end)

test("Haken: Voreinstellungen angezeigt, Klick schreibt in die BotpadDB", function()
   boot()
   local want = { Shown = true, MinimapButton = true, ResetOnStop = true, HideCommands = true,
                  ConfirmTp = true, Debug = false }
   for key, on in pairs(want) do
      local cb = optCheck(key)
      check(cb ~= nil, "Haken fuer " .. key)
      if cb then eq(cb:GetChecked() == 1, on, "Anzeige " .. key) end
   end
   for key in pairs(want) do
      local cb = optCheck(key)
      local before = Botpad.GetBool(key)
      click(cb)
      eq(Botpad.GetBool(key), not before, "Klick schaltet " .. key)
      click(cb)
      eq(Botpad.GetBool(key), before, "und zurueck " .. key)
   end
end)

test("Haken wirken sofort: Fenster und Minimap-Knopf", function()
   boot()
   local panel, mini = _G.BotpadPanel, _G.BotpadMinimapButton
   check(panel.__shown ~= false and mini.__shown ~= false, "zunaechst beides sichtbar")
   click(optCheck("Shown"))
   eq(panel.__shown, false, "Fenster aus")
   click(optCheck("MinimapButton"))
   eq(mini.__shown, false, "Knopf aus")
   click(optCheck("Shown"))
   click(optCheck("MinimapButton"))
   eq(panel.__shown, true, "Fenster wieder an")
   eq(mini.__shown, true, "Knopf wieder an")

   -- das Schliessen im Fenster und /bp stellen den Haken nach
   Botpad.UI.Toggle()
   eq(optCheck("Shown"):GetChecked(), nil, "Haken folgt dem Fenster (/bp)")
   Botpad.UI.Toggle()
   eq(optCheck("Shown"):GetChecked(), 1, "und wieder")
end)

test("bisherige Spielstaende bekommen die neue Einstellung (Minimap-Knopf an)", function()
   boot(nil, { Mode = "grind", ConfirmTp = 0 })
   eq(BotpadDB.MinimapButton, 1, "Standard ergaenzt")
   eq(BotpadDB.Mode, "grind", "eigener Wert bleibt")
   eq(_G.BotpadMinimapButton.__shown, true, "Knopf sichtbar")
   eq(optCheck("ConfirmTp"):GetChecked(), nil, "eigener Wert in der Anzeige")
   eq(modeButton("grind").selected, true, "gewaehlter Modus hervorgehoben")
end)

test("Modus: Knopf waehlt, /bp modus stellt die Hervorhebung nach", function()
   boot()
   eq(modeButton("normal").selected, true, "Normal ist Voreinstellung")
   modeButton("grind").__scripts.OnClick(modeButton("grind"))
   eq(BotpadDB.Mode, "grind", "gespeichert")
   eq(modeButton("grind").selected, true, "Grind hervorgehoben")
   eq(modeButton("normal").selected, false, "Normal nicht mehr")
   SlashCmdList["BOTPAD"]("modus minimal")
   eq(modeButton("minimal").selected, true, "nach /bp modus minimal")
   eq(modeButton("grind").selected, false, "Grind nicht mehr")

   -- ist der Selbstmodus an, wird der neue Modus gleich angewendet
   W.ServerLine("SelfBot is now active.")
   W.Advance(5)
   W.ClearSent()
   modeButton("grind").__scripts.OnClick(modeButton("grind"))
   W.Advance(5)
   local nc = false
   for _, x in ipairs(W.sent) do if x.channel == "WHISPER" and x.text:find("^nc ") then nc = true end end
   check(nc, "Strategien des neuen Modus gesendet")
end)

test("Umschaltbefehl: Eingabe mit Punkt wird gespeichert, ohne Punkt abgelehnt", function()
   boot()
   local eb = optEdit(1)
   check(eb ~= nil, "Eingabefeld")
   eq(eb:GetText(), ".playerbots bot self", "zeigt den Standard")

   enter(eb, ".playerbots bot self2")
   eq(BotpadDB.SelfCommand, ".playerbots bot self2", "gespeichert")

   enter(eb, "playerbots bot self")
   eq(BotpadDB.SelfCommand, ".playerbots bot self2", "ohne Punkt abgelehnt (er ginge in /sagen)")
   check(warned("mit einem Punkt beginnen"), "Spieler wird gewarnt")
   eq(eb:GetText(), ".playerbots bot self2", "Feld zeigt wieder den gueltigen Wert")

   enter(eb, "")
   eq(BotpadDB.SelfCommand, ".playerbots bot self", "leer = Standard")

   BotpadDB.SelfCommand = ".x"
   optionsButton("Standard").__scripts.OnClick(optionsButton("Standard"))
   eq(BotpadDB.SelfCommand, ".playerbots bot self", "Knopf Standard")

   -- dasselbe gilt fuer den Slash-Befehl
   SlashCmdList["BOTPAD"]("befehl ohnepunkt")
   eq(BotpadDB.SelfCommand, ".playerbots bot self", "/bp befehl ohne Punkt abgelehnt")
   SlashCmdList["BOTPAD"]("befehl .mein befehl")
   eq(BotpadDB.SelfCommand, ".mein befehl", "/bp befehl mit Punkt")
   eq(optEdit(1):GetText(), ".mein befehl", "die Seite folgt")
end)

test("Karten-ID erzwingen: Zahl wird gespeichert, 0 oder leer ist automatisch", function()
   boot()
   local eb = optEdit(2)
   enter(eb, "12")
   eq(BotpadDB.ForcedMapId, 12, "gespeichert")
   enter(eb, "0")
   eq(BotpadDB.ForcedMapId, nil, "0 = automatisch")
   enter(eb, "14")
   enter(eb, "")
   eq(BotpadDB.ForcedMapId, nil, "leer = automatisch")
   enter(eb, "14")
   enter(eb, "abc")
   eq(BotpadDB.ForcedMapId, 14, "Unsinn aendert nichts (kein stilles Loeschen)")
   check(warned("Keine gueltige Karten-ID"), "Spieler wird gewarnt")
   enter(eb, "1 2")
   eq(BotpadDB.ForcedMapId, 14, "'1 2' ebenso")
   enter(eb, "0x10")
   eq(BotpadDB.ForcedMapId, 14, "Hexzahl ebenso")
   enter(eb, "1e3")
   eq(BotpadDB.ForcedMapId, 14, "Exponent ebenso")
   enter(eb, "100000")
   eq(BotpadDB.ForcedMapId, 14, "unplausibel grosse Zahl ebenso")
   enter(eb, "99999")
   eq(BotpadDB.ForcedMapId, 99999, "Obergrenze gilt noch")
   enter(eb, "14")
   enter(eb, "")
   eq(BotpadDB.ForcedMapId, nil, "leer = automatisch")
   SlashCmdList["BOTPAD"]("karte 15")
   eq(eb:GetText(), "15", "/bp karte stellt das Feld nach")
end)

test("Teleport-Knopf auf der Seite loest den Handschlag aus", function()
   boot()
   installCarbonite()
   BotpadDB.ConfirmTp = 0
   local b = optionsButton("Jetzt zum Ziel teleportieren")
   check(b ~= nil, "Knopf")
   b.__scripts.OnClick(b)
   W.Advance(1)
   eq(count(".at hello"), 1, "Handschlag gesendet")
end)

test("Alle Einstellungen zuruecksetzen: Voreinstellung, Fensterlage bleibt", function()
   boot()
   BotpadDB.Mode = "grind"
   BotpadDB.SelfCommand = ".x"
   BotpadDB.HideCommands = 0
   BotpadDB.ConfirmTp = 0
   BotpadDB.Debug = 1
   BotpadDB.ForcedMapId = 99
   BotpadDB.MinimapAngle = 77
   BotpadDB.Point = { "TOP", 1, 2 }
   BotpadDB.Shown = 0
   Botpad.Options.Load()
   local b = optionsButton("Alle Einstellungen zuruecksetzen")
   b.__scripts.OnClick(b)
   eq(BotpadDB.Mode, "normal", "Modus")
   eq(BotpadDB.SelfCommand, ".playerbots bot self", "Befehl")
   eq(BotpadDB.HideCommands, 1, "HideCommands")
   eq(BotpadDB.ConfirmTp, 1, "ConfirmTp")
   eq(BotpadDB.Debug, 0, "Debug")
   eq(BotpadDB.ForcedMapId, nil, "Karten-ID")
   eq(BotpadDB.MinimapAngle, 77, "Knopfwinkel bleibt")
   eq(BotpadDB.Point[1], "TOP", "Fensterlage bleibt")
   eq(BotpadDB.Shown, 0, "Sichtbarkeit bleibt")
   eq(modeButton("normal").selected, true, "Anzeige folgt")
   eq(optCheck("Debug"):GetChecked(), nil, "Haken folgt")
   eq(optEdit(1):GetText(), ".playerbots bot self", "Eingabefeld folgt")

   SlashCmdList["BOTPAD"]("modus grind")
   SlashCmdList["BOTPAD"]("standard")
   eq(BotpadDB.Mode, "normal", "/bp standard")
end)

test("die Seite oeffnen: /bp optionen, Kopfzeilenknopf, Minimap mit Umschalt", function()
   boot()
   SlashCmdList["BOTPAD"]("optionen")
   eq(#opened, 2, "zweimal geoeffnet (3.3.5a braucht zwei Aufrufe)")
   check(opened[1] == _G.BotpadOptionsPanel and opened[2] == _G.BotpadOptionsPanel, "die richtige Seite")

   opened = {}
   local hb = optionsButton("|cffaaaaaa..|r")
   check(hb ~= nil, "Knopf in der Kopfzeile")
   hb.__scripts.OnClick(hb)
   eq(#opened, 2, "Kopfzeilenknopf")

   opened = {}
   W.world.shift = true
   _G.BotpadMinimapButton.__scripts.OnClick(_G.BotpadMinimapButton, "LeftButton")
   W.world.shift = false
   eq(#opened, 2, "Umschalt+Klick auf den Minimap-Knopf")
   eq(count(".playerbots"), 0, "und der Bot wurde dabei nicht umgeschaltet")

   opened = {}
   SlashCmdList["BOTPAD"]("einstellungen")
   SlashCmdList["BOTPAD"]("options")
   eq(#opened, 4, "Aliase")
end)

test("Statuszeile der Seite folgt Servermodul und Selbstmodus", function()
   boot()
   local function text() return _G.BotpadOptionsContent and Botpad.Options.status:GetText() or "" end
   check(text():find("noch nicht abgefragt", 1, true), "vor dem Handschlag")
   hello(63, 2)
   Botpad.Options.Load()
   check(text():find("bereit", 1, true), "nach dem Handschlag: bereit")
   check(text():find("Teleport erlaubt", 1, true), "Teleport erlaubt")
   hello(0, 0)
   Botpad.Options.Load()
   check(text():find("nicht erlaubt", 1, true), "ohne Berechtigung")
   W.ServerLine("SelfBot is now active.")
   W.Advance(5)
   check(text():find("Selbstmodus: ", 1, true), "Selbstmodus erscheint")
end)

-- ---------------------------------------------------------------------------
-- Zusammenspiel mit AutoTravel (Einstellungen, Meldungen, Filter)
-- ---------------------------------------------------------------------------

test("mit AutoTravel: Hinweis auf der Seite, Modus und Zuruecksetzen gesperrt", function()
   boot(function(name) return name == "AutoTravel" end)
   check(Botpad.autoTravel, "erkannt, bevor die Seite gebaut wird")
   check(Botpad.Options.autoNote ~= nil, "Hinweis auf der Seite")
   for _, m in ipairs(Botpad.Bot.Modes) do
      local b = modeButton(m.key)
      eq(b:IsEnabled(), nil, "Modusknopf gesperrt: " .. m.key)
   end
   eq(optCheck("ResetOnStop"):IsEnabled(), nil, "Zuruecksetzen gesperrt")
   check(optCheck("ResetOnStop"):GetAlpha() < 1, "gesperrte Zeile ist abgeblendet")
   check(modeButton("grind"):GetAlpha() < 1, "ebenso der Modusknopf")
   check(optCheck("ConfirmTp"):GetAlpha() == nil or optCheck("ConfirmTp"):GetAlpha() == 1, "bedienbare Zeile nicht")
   check(optCheck("ResetOnStop").gatedNote ~= nil, "mit Begruendung im Tooltip")
   check(optCheck("HideCommands").gatedNote ~= nil, "Befehle verbergen: nur ein Hinweis")
   eq(optCheck("HideCommands"):IsEnabled(), 1, "... aber nicht gesperrt")
   eq(optCheck("ConfirmTp"):IsEnabled(), 1, "Teleport-Abfrage bleibt bedienbar")
   eq(optCheck("MinimapButton"):IsEnabled(), 1, "Minimap-Knopf bleibt bedienbar")

   -- ein Klick (falls doch einer durchkommt) aendert nichts
   modeButton("grind").__scripts.OnClick(modeButton("grind"))
   eq(BotpadDB.Mode, "normal", "Modus unveraendert")
   check(warned("AutoTravel steuert den Playerbot"), "Hinweis")
end)

test("ohne AutoTravel gibt es keinen Hinweis, alles ist bedienbar", function()
   boot()
   eq(Botpad.autoTravel, false, "nicht erkannt")
   eq(Botpad.Options.autoNote, nil, "kein Hinweis")
   eq(modeButton("grind"):IsEnabled(), 1, "Modusknopf frei")
   eq(optCheck("ResetOnStop"):IsEnabled(), 1, "Zuruecksetzen frei")
end)

test("mit AutoTravel: keine doppelten Meldungen, Filter ueberlaesst ihm die Zeilen", function()
   boot(function(name) return name == "AutoTravel" end)
   W.messages = {}
   W.Fire("CHAT_MSG_SYSTEM", "[AT]M|Das Ziel liegt auf einer anderen Karte")
   eq(#W.messages, 0, "Botpad gibt die Meldung nicht noch einmal aus")
   check(not W.Filtered("CHAT_MSG_SYSTEM", "[AT]M|Das Ziel liegt auf einer anderen Karte"),
         "und verbirgt sie nicht (HideProtocol von AutoTravel entscheidet)")
   check(not W.Filtered("CHAT_MSG_SYSTEM", "[AT]S|IDLE|0|-|0|0|0|0|0|0"), "auch den Status nicht")
   -- der eigene Handschlag laeuft weiter: Teleport braucht ihn
   installCarbonite()
   BotpadDB.ConfirmTp = 0
   Botpad.Teleport()
   W.Advance(1)
   eq(count(".at hello"), 1, "Handschlag trotzdem")
   hello(63, 2)
   W.Advance(1)
   eq(count(".at tp"), 1, "Teleport trotzdem")

   -- ohne AutoTravel: Botpad zeigt sie selbst und verbirgt die rohe Zeile
   boot()
   W.messages = {}
   W.Fire("CHAT_MSG_SYSTEM", "[AT]M|Hallo Welt")
   check(warned("Hallo Welt"), "Botpad gibt sie aus")
   eq(#W.messages, 1, "genau einmal")
end)

test("mit AutoTravel setzt auch das Ausschalten keine Strategien zurueck", function()
   boot(function(name) return name == "AutoTravel" end)
   W.ServerLine("SelfBot is now active.")
   W.Advance(5)
   W.ClearSent()
   Botpad.ToggleBot()                      -- ausschalten, ResetOnStop ist an
   W.Advance(5)
   local whispers = 0
   for _, x in ipairs(W.sent) do if x.channel == "WHISPER" then whispers = whispers + 1 end end
   eq(whispers, 0, "keine Strategiebefehle beim Ausschalten")
   eq(count(".playerbots bot self"), 1, "der Umschalter selbst geht hinaus")
end)

test("ohne AutoTravel setzt das Ausschalten die Strategien zurueck", function()
   boot()
   W.ServerLine("SelfBot is now active.")
   W.Advance(5)
   W.ClearSent()
   Botpad.ToggleBot()
   W.Advance(5)
   local reset = false
   for _, x in ipairs(W.sent) do if x.channel == "WHISPER" and x.text == "nc !" then reset = true end end
   check(reset, "nc ! vor dem Umschalter")
end)


-- ---------------------------------------------------------------------------
-- Nachbesserungen nach der Durchsicht
-- ---------------------------------------------------------------------------

test("IsServerCommand: Punkt oder '!' mit einem Zeichen dahinter, wie der Core", function()
   boot()
   local f = Botpad.IsServerCommand
   check(f(".playerbots bot self"), "Punkt")
   check(f("!playerbots bot self"), "'!' ist ebenfalls ein Befehlsvorsatz")
   check(not f("playerbots bot self"), "ohne Vorsatz")
   check(not f("."), "nur ein Punkt")
   check(not f(". x"), "Punkt, Leerzeichen")
   check(not f("..x"), "zwei Punkte (der Core ignoriert sie)")
   check(not f("!!x"), "zwei Ausrufezeichen")
   check(not f(""), "leer")
   check(not f(nil), "nil")
end)

test("ein frueher gespeicherter Befehl ohne Punkt wird nie als Chat gesendet", function()
   boot(nil, { SelfCommand = "playerbots bot self" })
   eq(BotpadDB.SelfCommand, ".playerbots bot self", "beim Laden zurueckgesetzt")
   check(warned("beginnt nicht mit einem Punkt"), "Spieler wird informiert")

   -- der letzte Riegel: auch ein spaeter eingeschleuster Wert geht nicht hinaus
   BotpadDB.SelfCommand = "bot self"
   Botpad.ToggleBot()
   W.Advance(2)
   for _, x in ipairs(W.sent) do
      check(x.channel ~= "SAY" or x.text:sub(1, 1) == ".", "nichts ohne Punkt in /sagen: " .. tostring(x.text))
   end
   eq(BotpadDB.SelfCommand, ".playerbots bot self", "auf den Standard gesetzt")
   eq(count(".playerbots bot self"), 1, "der Standardbefehl ging hinaus")
end)

test("die Statuszeile der Seite folgt Handschlag und Selbstmodus von selbst", function()
   boot()
   local function text() return Botpad.Options.status:GetText() end
   check(text():find("noch nicht abgefragt", 1, true), "vorher")
   hello(63, 2)
   check(text():find("bereit", 1, true), "Handschlag: bereit, ohne Load()")
   W.ServerLine("SelfBot is now active.")
   check(text():find("Selbstmodus: |cff53d17aan", 1, true), "Selbstmodus an")
   W.ServerLine("SelfBot is now deactivated.")
   check(text():find("Selbstmodus: |cff8a90a0aus", 1, true), "Selbstmodus aus")
   check(text():find("Carbonite: |cffe8654anicht gefunden", 1, true), "Carbonite fehlt")
   installCarbonite()
   Botpad.Options.Load()
   check(text():find("Carbonite: |cff53d17agefunden", 1, true), "Carbonite da")
   W.ServerLine("[AT]H|4.0|0|0|0|0|4|0|0")
   check(text():find("abgeschaltet", 1, true), "Modul abgeschaltet")
end)

test("Zuruecksetzen wendet den Modus auf einen laufenden Bot an", function()
   boot()
   BotpadDB.Mode = "grind"
   W.ServerLine("SelfBot is now active.")
   W.Advance(5)
   W.ClearSent()
   SlashCmdList["BOTPAD"]("standard")
   W.Advance(5)
   eq(BotpadDB.Mode, "normal", "zurueckgesetzt")
   local nc = false
   for _, x in ipairs(W.sent) do
      if x.channel == "WHISPER" and x.text:find("^nc ") and not x.text:find("grind", 1, true) then nc = true end
   end
   check(nc, "Strategien von Normal gesendet")

   -- Modus unveraendert: nichts senden
   W.ClearSent()
   SlashCmdList["BOTPAD"]("standard")
   W.Advance(5)
   local n = 0
   for _, x in ipairs(W.sent) do if x.channel == "WHISPER" then n = n + 1 end end
   eq(n, 0, "keine Wiederholung, wenn sich der Modus nicht aendert")

   -- unter AutoTravel nie
   boot(function(name) return name == "AutoTravel" end)
   BotpadDB.Mode = "grind"
   W.ServerLine("SelfBot is now active.")
   W.ClearSent()
   SlashCmdList["BOTPAD"]("standard")
   W.Advance(5)
   n = 0
   for _, x in ipairs(W.sent) do if x.channel == "WHISPER" then n = n + 1 end end
   eq(n, 0, "mit AutoTravel keine Strategiebefehle")
end)

test("Chatfilter: [AT] nur bei Systemmeldungen, fremde Fluesternachrichten bleiben", function()
   boot()
   local function filtered(event, msg)
      for _, fn in ipairs(W.filters[event] or {}) do
         if fn({}, event, msg, "Fremder") then return true end
      end
      return false
   end
   check(filtered("CHAT_MSG_SYSTEM", "[AT]M|Hallo"), "System: verborgen")
   check(not filtered("CHAT_MSG_WHISPER", "[AT]Mein Freund hier"), "Fluestern eines anderen Spielers: sichtbar")
   check(not filtered("CHAT_MSG_WHISPER_INFORM", "[AT]Mein Freund hier"), "eigene Fluesterantwort: sichtbar")
end)

test("mit AutoTravel: der Modus gilt nicht, auch nicht ueber /bp modus und das Fenster", function()
   boot(function(name) return name == "AutoTravel" end)
   eq(Botpad.Bot.SetMode("grind"), false, "SetMode lehnt ab")
   SlashCmdList["BOTPAD"]("modus grind")
   eq(BotpadDB.Mode, "normal", "nicht gespeichert")
   check(warned("AutoTravel steuert den Playerbot"), "Hinweis")
   check(not warned("Modus: |cffffffffGrind"), "keine falsche Erfolgsmeldung")
   boot()
   eq(Botpad.Bot.SetMode("grind"), true, "ohne AutoTravel geht es")
   eq(BotpadDB.Mode, "grind", "gespeichert")
end)

test("ein unbekannter gespeicherter Modus faellt auf Normal zurueck", function()
   boot(nil, { Mode = "gibtsnicht" })
   eq(Botpad.Bot.Current().key, "normal", "Normal")
end)

test("neue Slash-Befehle: knopf, strategien, verbergen", function()
   boot()
   SlashCmdList["BOTPAD"]("knopf")
   eq(BotpadDB.MinimapButton, 0, "Knopf aus")
   eq(_G.BotpadMinimapButton.__shown, false, "Knopf verborgen")
   eq(optCheck("MinimapButton"):GetChecked(), nil, "Haken folgt")
   SlashCmdList["BOTPAD"]("knopf")
   eq(_G.BotpadMinimapButton.__shown, true, "wieder da")
   SlashCmdList["BOTPAD"]("strategien")
   eq(BotpadDB.ResetOnStop, 0, "Strategien zuruecksetzen aus")
   eq(optCheck("ResetOnStop"):GetChecked(), nil, "Haken folgt")
   SlashCmdList["BOTPAD"]("verbergen")
   eq(BotpadDB.HideCommands, 0, "verbergen aus")
   eq(optCheck("HideCommands"):GetChecked(), nil, "Haken folgt")
   SlashCmdList["BOTPAD"]("nachfrage")
   eq(optCheck("ConfirmTp"):GetChecked(), nil, "nachfrage: Haken folgt")
   SlashCmdList["BOTPAD"]("debug")
   eq(optCheck("Debug"):GetChecked(), 1, "debug: Haken folgt")
end)

test("beim Anmelden bleiben verborgene Fenster und Knopf verborgen", function()
   boot(nil, { MinimapButton = 0, Shown = 0 })
   eq(_G.BotpadMinimapButton.__shown, false, "Knopf verborgen")
   eq(_G.BotpadPanel.__shown, false, "Fenster verborgen")
   eq(optCheck("MinimapButton"):GetChecked(), nil, "Haken passt")
end)

test("Neuinstallation: Knopf und Fenster ueberdecken die von AutoTravel nicht", function()
   boot()
   eq(BotpadDB.MinimapAngle, 160, "Winkel (AutoTravel: 200)")
   eq(BotpadDB.Shown, 1, "Fenster an")
end)

test("Eingabefelder: Enter speichert einmal, Maus verlassen speichert, Escape verwirft", function()
   boot()
   local eb = optEdit(1)
   local prints = 0
   local orig = Botpad.Print
   Botpad.Print = function(m) prints = prints + 1 return orig(m) end

   eb:SetText(".erster befehl")
   eb.__scripts.OnEnterPressed(eb)
   eb.__scripts.OnEditFocusLost(eb)           -- ClearFocus loest das im Client aus
   eq(BotpadDB.SelfCommand, ".erster befehl", "Enter")
   eq(prints, 1, "nur einmal gespeichert/gemeldet")

   eb:SetText(".zweiter befehl")
   eb.__scripts.OnEditFocusLost(eb)
   eq(BotpadDB.SelfCommand, ".zweiter befehl", "Fokus verloren = gespeichert")

   eb:SetText(".dritter befehl")
   eb.__scripts.OnEscapePressed(eb)
   eb.__scripts.OnEditFocusLost(eb)           -- ClearFocus
   eq(BotpadDB.SelfCommand, ".zweiter befehl", "Escape verwirft")
   eq(eb:GetText(), ".zweiter befehl", "Feld zeigt wieder den gespeicherten Wert")
   Botpad.Print = orig
end)

test("Seite: OnShow und refresh lesen die BotpadDB neu, Standard im Optionsfenster setzt zurueck", function()
   boot()
   local p = _G.BotpadOptionsPanel
   BotpadDB.Debug = 1                         -- hinter dem Ruecken der Seite geaendert
   eq(optCheck("Debug"):GetChecked(), nil, "noch alt")
   p.__scripts.OnShow(p)
   eq(optCheck("Debug"):GetChecked(), 1, "OnShow liest neu")
   BotpadDB.Debug = 0
   p.refresh()
   eq(optCheck("Debug"):GetChecked(), nil, "refresh liest neu")

   BotpadDB.Mode = "grind"
   BotpadDB.MinimapButton = 0
   p.default()
   eq(BotpadDB.Mode, "normal", "Standard: Modus")
   eq(BotpadDB.MinimapButton, 1, "Standard: Minimap-Knopf")
   eq(_G.BotpadMinimapButton.__shown, true, "Knopf wieder sichtbar")
   check(type(p.okay) == "function" and type(p.cancel) == "function", "okay/cancel vorhanden")
end)

test("Zuruecksetzen setzt jede Einstellung mit Voreinstellung zurueck", function()
   boot()
   for k, v in pairs(Botpad.DEFAULTS) do
      if k ~= "MinimapAngle" and k ~= "Shown" then
         BotpadDB[k] = (type(v) == "number") and (v == 1 and 0 or 1) or "x"
      end
   end
   BotpadDB.SelfCommand = ".anders"
   BotpadDB.Mode = "grind"
   SlashCmdList["BOTPAD"]("standard")
   for k, v in pairs(Botpad.DEFAULTS) do
      if k ~= "MinimapAngle" and k ~= "Shown" then
         eq(BotpadDB[k], v, "zurueckgesetzt: " .. k)
      end
   end
   eq(_G.BotpadMinimapButton.__shown, true, "Knopf sichtbar")
   eq(optCheck("ResetOnStop"):GetChecked(), 1, "Haken ResetOnStop")
end)

test("Minimap-Knopf: Linksklick schaltet den Bot, Rechtsklick das Fenster", function()
   boot()
   local mb = _G.BotpadMinimapButton
   mb.__scripts.OnClick(mb, "LeftButton")
   W.Advance(1)
   eq(count(".playerbots bot self"), 1, "Linksklick: Umschalter gesendet")
   mb.__scripts.OnClick(mb, "RightButton")
   eq(BotpadDB.Shown, 0, "Rechtsklick: Fenster aus")
   eq(optCheck("Shown"):GetChecked(), nil, "Haken folgt")
end)

test("Schliessen-Knopf des Fensters stellt den Haken nach", function()
   boot()
   local close = optionsButton("|cffaaaaaax|r")
   check(close ~= nil, "Schliessen-Knopf")
   close.__scripts.OnClick(close)
   eq(BotpadDB.Shown, 0, "Fenster aus")
   eq(optCheck("Shown"):GetChecked(), nil, "Haken folgt")
end)

test("Hover-Skripte laufen fehlerfrei (Tooltips der Seite)", function()
   boot(function(name) return name == "AutoTravel" end)
   local n = 0
   for _, f in ipairs(W.frames) do
      for _, ev in ipairs({ "OnEnter", "OnLeave" }) do
         if f.__scripts[ev] then
            local ok, err = pcall(f.__scripts[ev], f)
            check(ok, ev .. ": " .. tostring(err))
            n = n + 1
         end
      end
   end
   check(n > 10, "es gab Hover-Skripte (" .. n .. ")")
end)

-- ---------------------------------------------------------------------------
-- Beide Addons zusammen (nur wenn das AutoTravel-Addon daneben liegt)
-- ---------------------------------------------------------------------------

local function atDir()
   local dir = os.getenv("AT_CLIENT_DIR") or "../mod-autotravel_clientaddon"
   local f = io.open(dir .. "/AutoTravel.toc", "r")
   if not f then return nil end
   f:close()
   return dir
end

local function bootBoth(dir)
   W.Install()
   added, opened = {}, {}
   _G.InterfaceOptions_AddCategory = function(f) added[#added + 1] = f end
   _G.InterfaceOptionsFrame_OpenToCategory = function(f) opened[#opened + 1] = f end
   _G.IsAddOnLoaded = function(name) return name == "AutoTravel" or name == "Botpad" end
   _G.BotpadDB = nil
   W.LoadToc(dir, "AutoTravel.toc")
   W.LoadToc(".", "Botpad.toc")
   W.Fire("ADDON_LOADED", "AutoTravel")
   W.Fire("ADDON_LOADED", "Botpad")
   W.Fire("PLAYER_LOGIN")
end

local function countMessages(text)
   local n = 0
   for _, m in ipairs(W.messages) do if m:find(text, 1, true) then n = n + 1 end end
   return n
end

test("mit dem echten AutoTravel zusammen: jede Meldung genau einmal", function()
   local dir = atDir()
   if not dir then
      io.write("   (uebersprungen: AutoTravel-Addon nicht gefunden; AT_CLIENT_DIR setzen)\n")
      return
   end
   bootBoth(dir)
   check(Botpad.autoTravel, "Botpad erkennt AutoTravel")
   local names = {}
   for _, f in ipairs(added) do names[f.name] = true end
   check(names["Botpad"] and names["AutoTravel"], "beide Seiten unter Interface -> AddOns")

   W.messages = {}
   W.ServerLine("[AT]M|Das Ziel liegt auf einer anderen Karte (Map 0)")
   eq(countMessages("anderen Karte (Map 0)"), 1, "Textmeldung: nur AutoTravel gibt sie aus")

   W.messages = {}
   W.ServerLine("[AT]H|4.0.5|0|0|0|0|4|0|0")
   eq(countMessages("abgeschaltet"), 1, "Modul abgeschaltet: einmal gemeldet")

   W.messages = {}
   W.ServerLine("SelfBot is restricted for this account.")
   eq(countMessages("SelfBot is restricted"), 1, "Verweigerung des Selbstmodus: einmal gemeldet")

   -- Botpad setzt keine Strategien (AutoTravel schickt seinen Satz selbst)
   eq(Botpad.Bot.disabled, true, "Strategiesteuerung bei Botpad aus")
end)

print(string.format("\n%d Pruefungen, %d Fehler", passes, failures))
os.exit(failures == 0 and 0 or 1)

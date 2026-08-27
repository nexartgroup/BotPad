-- BP_Bot.lua
-- ---------------------------------------------------------------------------
-- Playerbot-Selbstmodus und die drei Betriebsarten.
--
-- Alle Botbefehle gehen als Fluesternachricht an den eigenen Charakter -- so
-- erwartet es mod-playerbots fuer Einzelbots. Die Echos werden aus dem Chat
-- gefiltert, damit das Bedienfeld nicht dauernd Text produziert.
-- ---------------------------------------------------------------------------

Botpad = Botpad or {}
local BP = Botpad

BP.Bot = {}
local B = BP.Bot

-- ---------------------------------------------------------------------------
-- Modi
-- ---------------------------------------------------------------------------

B.Modes = {
    {
      key  = "buffbot",
      name = "BuffBot",
      desc = "Kein Sammeln, kein Looten ausser Quest und Beruf.",
      nc   = "+bdps,+chat,-default,-dps assist,-duel,+emote,-follow,-food,-gather,-loot,-mount,+nc,+pet,-pvp,-quest,+heal,+cure",
      co   = "-aoe,+avoid aoe,+bdps,+bm,+cast time,+cc,+chat,-default,+dps assist,+duel,+formation,+potions,+racials,+healer dps,+cure",
      ll   = "-all,+quest,+skill,-gray",
      ss   = "self" 
   },
   {
      key  = "minimal",
      name = "Minimal",
      desc = "Kein Sammeln, kein Looten ausser Quest und Beruf.",
      nc   = "+bdps,-chat,+default,+dps assist,-duel,-emote,+follow,+food,-gather,-loot,+mount,+nc,+pet,+pvp,+quest,+heal,+cure",
      co   = "+aoe,+avoid aoe,+bdps,+bm,+cast time,+cc,+chat,+default,+dps assist,+duel,+formation,+potions,+racials,+healer dps,+cure",
      ll   = "-all,+quest,+skill,-gray",
      ss   = "self" 
   },
   {
      key  = "normal",
      name = "Normal",
      desc = "Voller Funktionsumfang, normales Looten.",
      nc   = "+bdps,+chat,+default,+dps assist,+duel,+emote,+follow,+food,+gather,+loot,+mount,+nc,+pet,+pvp,+quest,+heal,+cure",
      co   = "+aoe,+avoid aoe,+bdps,+bm,+cast time,+cc,+chat,+default,+dps assist,+duel,+formation,+potions,+racials,+healer dps",
      ll   = "normal",
      ss   = "self" 
   },
   {
      key  = "grind",
      name = "Grind",
      desc = "Wie Normal, sucht zusaetzlich selbst Ziele.",
      nc   = "+bdps,+chat,+default,+dps assist,+duel,+emote,+follow,+food,+gather,+loot,+mount,+nc,+pet,+pvp,+quest,+grind,+cure",
      co   = "+aoe,+avoid aoe,+bdps,+bm,+cast time,+cc,+chat,+default,+dps assist,+duel,+formation,+potions,+racials,+healer dps,+cure,+heal",
      ll   = "normal",
      ss   = "self" 
   },
   {
      key  = "grind_loot",
      name = "Grind&Loot",
      desc = "Wie Normal, sucht zusaetzlich selbst Ziele.",
      nc   = "+bdps,+chat,+default,+dps assist,+duel,+emote,+follow,+food,+gather,+loot,+mount,+nc,+pet,+pvp,+quest,+grind,+cure",
      co   = "+aoe,+avoid aoe,+bdps,+bm,+cast time,+cc,+chat,+default,+dps assist,+duel,+formation,+potions,+racials,+healer dps,+cure,+heal",
      ll   = "all",
      ss   = "self" 
   },
}

function B.Find(key)
   for _, m in ipairs(B.Modes) do
      if m.key == key then return m end
   end
   return B.Modes[2]        -- Normal
end

function B.Current()
   return B.Find(BP.Get("Mode"))
end

-- ---------------------------------------------------------------------------
-- Senden
-- ---------------------------------------------------------------------------
-- Kleine Warteschlange: mehrere Befehle dicht hintereinander loesen sonst die
-- Flutbremse des Clients aus.

local queue, lastSent = {}, 0
local GAP = 0.35

local recent = {}         -- zum Ausblenden der eigenen Echos

local pump = CreateFrame("Frame", "BotpadSender")
pump:SetScript("OnUpdate", function()
   if #queue == 0 then return end
   local now = GetTime()
   if (now - lastSent) < GAP then return end
   local item = table.remove(queue, 1)
   lastSent = now
   item()
end)

-- Serverbefehl (".playerbot ..."). Wird serverseitig abgefangen und nie an
-- andere Spieler weitergegeben, der Kanal ist dafuer bedeutungslos.
function B.SendCommand(cmd)
   table.insert(queue, function()
      SendChatMessage(cmd, "SAY")
      BP.Debug("-> " .. cmd)
   end)
end

-- Botbefehl per Fluestern an den eigenen Charakter
function B.Whisper(text)
   if not text or text == "" then return end
   recent[text] = GetTime()
   table.insert(queue, function()
      SendChatMessage(text, "WHISPER", nil, UnitName("player"))
      BP.Debug("-> [an dich] " .. text)
   end)
end

function B.IsOwnCommand(msg)
   if type(msg) ~= "string" then return false end
   local t = recent[msg]
   return t and (GetTime() - t) < 20
end

-- ---------------------------------------------------------------------------
-- Zustand
-- ---------------------------------------------------------------------------
-- Der Server meldet das Umschalten im Chat. Das wird mitgelesen, statt den
-- Zustand zu vermuten -- so stimmt die Anzeige auch, wenn der Selbstmodus von
-- Hand geschaltet wurde.

B.running = nil           -- nil = unbekannt, true/false = bestaetigt

local ON_PATTERNS  = { "enable player botai", "playerbot ai enabled" }
local OFF_PATTERNS = { "disable player botai", "playerbot ai disabled" }

local function MatchAny(low, list)
   for _, p in ipairs(list) do
      if string.find(low, p, 1, true) then return true end
   end
   return false
end

function B.OnSystemMessage(msg)
   if type(msg) ~= "string" then return false end
   local low = string.lower(msg)

   if MatchAny(low, ON_PATTERNS) then
      B.running = true
      B.ApplyMode(true)          -- Strategien passend zum Modus setzen
      if BP.UI then BP.UI.Update() end
      return true
   end
   if MatchAny(low, OFF_PATTERNS) then
      B.running = false
      if BP.UI then BP.UI.Update() end
      return true
   end
   return false
end

function B.StatusText()
   if B.running == true  then return "|cff53d17aan|r" end
   if B.running == false then return "|cff8a90a0aus|r" end
   return "|cffe8c44a?|r"
end

-- ---------------------------------------------------------------------------
-- Umschalten
-- ---------------------------------------------------------------------------

local watchdog = CreateFrame("Frame")
local watchUntil = 0

watchdog:SetScript("OnUpdate", function()
   if watchUntil == 0 then return end
   if GetTime() < watchUntil then return end
   watchUntil = 0
   if B.running == nil then
      BP.Warn("Keine Bestaetigung vom Server. Stimmt der Befehl? Aktuell: "
              .. tostring(BP.Get("SelfCommand")))
      BP.Warn("Schreibweise mit '.playerbots help' pruefen, dann /botpad befehl <text>")
   end
end)

-- Der Befehl ist ein Umschalter: derselbe Aufruf schaltet ein und aus.
function B.Toggle()
   if B.running then B.ResetStrategies() end
   B.SendCommand(BP.Get("SelfCommand") or ".playerbot bot self")
   if B.running then B.ResetStrategies() end
   watchUntil = GetTime() + 6
end

-- ---------------------------------------------------------------------------
-- Modus anwenden
-- ---------------------------------------------------------------------------

function B.ApplyMode(silent)
   local m = B.Current()
   B.ResetStrategies()
   B.Whisper("nc " .. m.nc)
   B.Whisper("co " .. m.co)
   B.Whisper("ll " .. m.ll)
   B.Whisper("ss " .. m.ss)
   if not silent then
      BP.Print("Modus: |cffffffff" .. m.name .. "|r - " .. m.desc)
   end
end

function B.SetMode(key)
   BP.Set("Mode", key)
   local m = B.Current()
   BP.Print("Modus: |cffffffff" .. m.name .. "|r - " .. m.desc)
   if B.running then B.ApplyMode(true) end
   if BP.UI then BP.UI.Update() end
end

-- Beim Ausschalten die Strategien zuruecksetzen, damit der Charakter nicht
-- mit halb gesetzten Botstrategien zurueckbleibt.
function B.ResetStrategies()
   B.Whisper("ll normal")
   B.Whisper("nc !")
   B.Whisper("co !")
end

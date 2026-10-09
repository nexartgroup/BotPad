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
      desc = "Kein Sammeln, kein Looten.",
      nc   = "+bdps,+chat,-default,-dps assist,-duel,+emote,-follow,-food,-gather,-loot,-mount,+nc,+pet,-pvp,-quest,+heal,+cure",
      co   = "-aoe,+avoid aoe,+bdps,+bm,+cast time,+cc,+chat,-default,+dps assist,+duel,+formation,+potions,+racials,+healer dps,+cure",
      -- "ll" kennt nur all/*, gray/g und disenchant; jeder andere Wert wird zu
      -- "normal" (LootStrategyValue::instance in mod-playerbots). Das Looten
      -- schraenken hier die nc-Strategien -loot und -gather ein.
      ll   = "normal"
   },
   {
      key  = "minimal",
      name = "Minimal",
      desc = "Kein Sammeln, kein Looten.",
      nc   = "+bdps,-chat,+default,+dps assist,-duel,-emote,+follow,+food,-gather,-loot,+mount,+nc,+pet,+pvp,+quest,+heal,+cure",
      co   = "+aoe,+avoid aoe,+bdps,+bm,+cast time,+cc,+chat,+default,+dps assist,+duel,+formation,+potions,+racials,+healer dps,+cure",
      -- "ll" kennt nur all/*, gray/g und disenchant; jeder andere Wert wird zu
      -- "normal" (LootStrategyValue::instance in mod-playerbots). Das Looten
      -- schraenken hier die nc-Strategien -loot und -gather ein.
      ll   = "normal"
   },
   {
      key  = "normal",
      name = "Normal",
      desc = "Voller Funktionsumfang, normales Looten.",
      nc   = "+bdps,+chat,+default,+dps assist,+duel,+emote,+follow,+food,+gather,+loot,+mount,+nc,+pet,+pvp,+quest,+heal,+cure",
      co   = "+aoe,+avoid aoe,+bdps,+bm,+cast time,+cc,+chat,+default,+dps assist,+duel,+formation,+potions,+racials,+healer dps",
      ll   = "normal"
   },
   {
      key  = "grind",
      name = "Grind",
      desc = "Wie Normal, sucht zusaetzlich selbst Ziele.",
      nc   = "+bdps,+chat,+default,+dps assist,+duel,+emote,+follow,+food,+gather,+loot,+mount,+nc,+pet,+pvp,+quest,+grind,+cure",
      co   = "+aoe,+avoid aoe,+bdps,+bm,+cast time,+cc,+chat,+default,+dps assist,+duel,+formation,+potions,+racials,+healer dps,+cure,+heal",
      ll   = "normal"
   },
   {
      key  = "grind_loot",
      name = "Grind&Loot",
      desc = "Wie Normal, sucht zusaetzlich selbst Ziele.",
      nc   = "+bdps,+chat,+default,+dps assist,+duel,+emote,+follow,+food,+gather,+loot,+mount,+nc,+pet,+pvp,+quest,+grind,+cure",
      co   = "+aoe,+avoid aoe,+bdps,+bm,+cast time,+cc,+chat,+default,+dps assist,+duel,+formation,+potions,+racials,+healer dps,+cure,+heal",
      ll   = "all"
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
   item.fn()
end)

-- Serverbefehl (".playerbots ..."). Wird serverseitig abgefangen und nie an
-- andere Spieler weitergegeben, SOFERN der Befehl dort existiert. Ein unbekannter
-- Punktbefehl bringt einem normalen Spieler "Es gibt keinen solchen Befehl" --
-- und nur bei AllowPlayerCommands = 0 (nicht Standard) behandelt AzerothCore ihn
-- als gewoehnlichen Text (ChatHandler::_ParseCommands), den der Charakter dann in
-- /sagen riefe.
function B.SendCommand(cmd)
   table.insert(queue, { tag = "cmd", fn = function()
      SendChatMessage(cmd, "SAY")
      BP.Debug("-> " .. cmd)
   end })
end

-- Botbefehl per Fluestern an den eigenen Charakter
function B.Whisper(text)
   if not text or text == "" then return end
   recent[text] = GetTime()
   table.insert(queue, { tag = "bot", fn = function()
      SendChatMessage(text, "WHISPER", nil, UnitName("player"))
      BP.Debug("-> [an dich] " .. text)
   end })
end

-- Wartende Fluesterbefehle verwerfen (z. B. wenn der Server den Selbstmodus
-- verweigert und die Strategiebefehle dahinter sinnlos sind).
function B.DropWhispers()
   for i = #queue, 1, -1 do
      if queue[i].tag == "bot" then table.remove(queue, i) end
   end
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
B.disabled = false        -- true: ein anderes Addon (AutoTravel) steuert den Bot

local watchUntil = 0      -- Frist fuer die Bestaetigung; VOR den Funktionen, die sie lesen

-- Die Meldungen von mod-playerbots haben sich geaendert. Heute (PlayerbotMgr.cpp,
-- Befehl "self"):
--     "SelfBot is now active."                       eingeschaltet
--     "SelfBot is now deactivated."                  ausgeschaltet
--     "SelfBot is disabled server-wide."             AiPlayerbot.SelfBotLevel = 0
--     "SelfBot is restricted for this account."      SelfBotLevel = 1, kein Spielleiter
-- Aeltere Staende meldeten "Enable/Disable player botAI". Beide Fassungen werden
-- erkannt.
local ON_PATTERNS     = { "selfbot is now active", "enable player botai", "playerbot ai enabled" }
local OFF_PATTERNS    = { "selfbot is now deactivated", "disable player botai", "playerbot ai disabled" }
local REFUSE_PATTERNS = { "selfbot is disabled server-wide", "selfbot is restricted for this account",
                          "playerbot system is currently disabled",   -- AiPlayerbot.Enabled = 0
                          "you cannot control bots yet" }             -- noch kein Bot-Verwalter

local watchWant = nil     -- gewuenschter Zustand der letzten Umschaltung
local watchRetried = false
local SendToggle          -- unten definiert

local function MatchAny(low, list)
   for _, p in ipairs(list) do
      if string.find(low, p, 1, true) then return true end
   end
   return false
end

-- ".playerbots bot self" ist ein Umschalter. Ist der Zustand unbekannt (nach
-- /reload, oder der Server hat den Selbstmodus beim Anmelden selbst eingeschaltet),
-- kehrt ein Klick ihn um. Kommt innerhalb der Wartezeit die Bestaetigung des
-- GEGENTEILS, wird einmal erneut umgeschaltet. Rueckgabe: true, wenn umgeschaltet
-- wird (dann ist die Strategieanwendung fuer diese Bestaetigung hinfaellig).
local function Reconcile()
   if watchUntil == 0 or watchWant == nil then return false end
   if B.running == watchWant then watchUntil = 0 return false end
   if watchRetried then
      watchUntil = 0
      BP.Warn("Der Selbstmodus liess sich nicht in den gewuenschten Zustand bringen. " ..
              "Er ist " .. (B.running and "an" or "aus") .. ".")
      return false
   end
   watchRetried = true
   B.DropWhispers()
   SendToggle(watchWant, true)
   return true
end

function B.OnSystemMessage(msg)
   if type(msg) ~= "string" then return false end
   local low = string.lower(msg)

   if MatchAny(low, REFUSE_PATTERNS) then
      -- Keine Fehlbedienung: der Server verweigert den Selbstmodus. Die
      -- Strategiebefehle dahinter waeren sinnlos, die Fristueberwachung soll
      -- nicht zusaetzlich meckern.
      B.running = false
      watchUntil = 0
      B.DropWhispers()
      BP.Warn("Der Server verweigert den Selbstmodus: " .. msg ..
              " (AiPlayerbot.SelfBotLevel in der Serverkonfiguration)")
      if BP.UI then BP.UI.Update() end
      return true
   end

   if MatchAny(low, ON_PATTERNS) then
      B.running = true
      if not Reconcile() and not B.disabled then
         B.ApplyMode(true)       -- Strategien passend zum Modus setzen
      end
      if BP.UI then BP.UI.Update() end
      return true
   end
   if MatchAny(low, OFF_PATTERNS) then
      B.running = false
      Reconcile()
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
--
-- Beim Ausschalten werden die Strategien VOR dem Umschalter zurueckgesetzt. Die
-- Fassung davor tat es zusaetzlich danach (und noch einmal in BP.ToggleBot):
-- ohne KI antwortet niemand auf die Fluesterbefehle, und aus einem Klick wurden
-- zehn gedrosselte Nachrichten.
function SendToggle(want, isRetry)
   B.SendCommand(BP.Get("SelfCommand") or ".playerbots bot self")
   if not isRetry then watchRetried = false end
   watchWant = want
   watchUntil = GetTime() + 6
end

function B.Toggle()
   -- Gewuenscht ist das Gegenteil des bekannten Zustands; bei unbekanntem Zustand
   -- zeigt der Knopf "BOT EIN", gewuenscht ist also "an".
   local want = (B.running ~= true)
   if not want and BP.GetBool("ResetOnStop") then
      B.ResetStrategies()
   end
   SendToggle(want, false)
end

-- ---------------------------------------------------------------------------
-- Modus anwenden
-- ---------------------------------------------------------------------------

function B.ApplyMode(silent)
   if B.disabled then return end
   local m = B.Current()
   B.ResetStrategies()
   B.Whisper("nc " .. m.nc)
   B.Whisper("co " .. m.co)
   B.Whisper("ll " .. m.ll)
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
   if BP.Options then BP.Options.Refresh() end
end

-- Beim Ausschalten die Strategien zuruecksetzen, damit der Charakter nicht
-- mit halb gesetzten Botstrategien zurueckbleibt.
function B.ResetStrategies()
   if B.disabled then return end      -- AutoTravel steuert die Strategien
   B.Whisper("ll normal")
   B.Whisper("nc !")
   B.Whisper("co !")
end

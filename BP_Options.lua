-- BP_Options.lua
-- ---------------------------------------------------------------------------
-- Einstellungsseite unter Interface -> AddOns -> Botpad.
--
-- Alles, was hier steht, laesst sich auch per Slash-Befehl setzen (/bp ...; die
-- Zuordnung steht in der Hilfe, /bp ohne Argument ausser dem Fenster); die Seite
-- ist nur die bequeme Variante. Beide Wege schreiben in dieselbe BotpadDB.
--
-- Die Seite liegt in einem ScrollFrame, damit nichts ausserhalb des sichtbaren
-- Bereichs des Optionsfensters landet, und die Zeilen werden fortlaufend gezaehlt.
-- ---------------------------------------------------------------------------

local BP = Botpad
BP.Options = {}
local O = BP.Options

local frame, content
local widgets = {}        -- alles, was beim Laden der Seite aus der BotpadDB gelesen wird
local modeButtons = {}
local gated = {}          -- Bedienelemente, die gesperrt sind, solange AutoTravel den Bot steuert

local WIDTH = 580

-- ---------------------------------------------------------------------------
-- Bausteine
-- ---------------------------------------------------------------------------

local function Header(parent, text, x, y)
   local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
   fs:SetPoint("TOPLEFT", x, y)
   fs:SetText(text)
   fs:SetTextColor(0.35, 0.71, 0.91)

   local line = parent:CreateTexture(nil, "ARTWORK")
   line:SetTexture("Interface\\Buttons\\WHITE8X8")
   line:SetVertexColor(0.25, 0.28, 0.33, 0.8)
   line:SetPoint("TOPLEFT", x, y - 18)
   line:SetWidth(WIDTH - x) line:SetHeight(1)
   return fs
end

local function Note(parent, text, x, y, width)
   local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
   fs:SetPoint("TOPLEFT", x, y)
   fs:SetWidth(width or (WIDTH - x - 10))
   fs:SetJustifyH("LEFT")
   fs:SetText(text)
   return fs
end

local checkCount = 0
local function Check(parent, label, tip, x, y, key, onChange)
   checkCount = checkCount + 1
   local name = "BotpadOptCheck" .. checkCount
   local cb = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
   cb:SetPoint("TOPLEFT", x, y)
   cb:SetWidth(24) cb:SetHeight(24)

   local fs = _G[name .. "Text"]
   if fs then
      fs:SetText(label)
      fs:SetFontObject("GameFontHighlightSmall")
   end
   cb.text = fs
   cb.key = key

   cb:SetScript("OnEnter", function()
      GameTooltip:SetOwner(cb, "ANCHOR_RIGHT")
      GameTooltip:AddLine(label)
      if tip then GameTooltip:AddLine(tip, 0.7, 0.7, 0.7, true) end
      if cb.gatedNote then
         GameTooltip:AddLine(" ")
         GameTooltip:AddLine(cb.gatedNote, 0.91, 0.65, 0.29, true)
      end
      GameTooltip:Show()
   end)
   cb:SetScript("OnLeave", function() GameTooltip:Hide() end)

   cb:SetScript("OnClick", function()
      local v = cb:GetChecked() and 1 or 0
      BP.Set(key, v)
      if onChange then onChange(v) end
   end)

   cb.Load = function() cb:SetChecked(BP.GetBool(key)) end
   table.insert(widgets, cb)
   return cb
end

local editCount = 0
-- Eingabefeld; onEnter(text) -> true, wenn der Wert angenommen wurde
local function Edit(parent, label, x, y, width, load, onEnter)
   editCount = editCount + 1
   local lbl = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
   lbl:SetPoint("TOPLEFT", x, y)
   lbl:SetText(label)

   local eb = CreateFrame("EditBox", "BotpadOptEdit" .. editCount, parent, "InputBoxTemplate")
   eb:SetPoint("TOPLEFT", x + 4, y - 16)
   eb:SetWidth(width) eb:SetHeight(20)
   eb:SetAutoFocus(false)

   -- Enter speichert; wer das Feld mit der Maus verlaesst, hat ebenfalls gemeint, was
   -- er getippt hat. Escape verwirft. 'skip' verhindert das doppelte Speichern, weil
   -- ClearFocus selbst OnEditFocusLost ausloest.
   local function commit()
      onEnter(BP.trim(eb:GetText()))
      eb.Load()
   end
   eb:SetScript("OnEnterPressed", function()
      eb.skip = true
      eb:ClearFocus()
      commit()
   end)
   eb:SetScript("OnEscapePressed", function()
      eb.skip = true
      eb:ClearFocus()
      eb.Load()
   end)
   eb:SetScript("OnEditFocusLost", function()
      if eb.skip then eb.skip = false return end
      commit()
   end)

   eb.Load = function() eb:SetText(load() or "") end
   eb.label = lbl
   table.insert(widgets, eb)
   return eb
end

-- ---------------------------------------------------------------------------
-- Zustand
-- ---------------------------------------------------------------------------

local function StatusText()
   local s = BP.srv
   local lines = {}

   if s.state == "READY" then
      local tp = (not s.capsKnown or (math.floor(s.caps / 8) % 2) == 1) and "erlaubt" or "nicht erlaubt"
      lines[#lines + 1] = string.format("Servermodul: |cff53d17abereit|r  -  Version %s, Kontostufe %d, Teleport %s",
                                        tostring(s.version), s.sec, tp)
   elseif s.state == "HELLO" then
      lines[#lines + 1] = "Servermodul: |cffe8c44aAnfrage laeuft ...|r"
   elseif s.state == "DISABLED" then
      lines[#lines + 1] = "Servermodul: |cffe8654aabgeschaltet|r  -  mod-autotravel ist auf dem Server aus."
   else
      lines[#lines + 1] = "Servermodul: |cff9099a8noch nicht abgefragt|r  (wird beim ersten Teleport gefragt)"
   end

   lines[#lines + 1] = "Selbstmodus: " .. BP.Bot.StatusText()
   lines[#lines + 1] = "Carbonite: " .. (BP.Carb.IsAvailable() and "|cff53d17agefunden|r" or "|cffe8654anicht gefunden|r")
   return table.concat(lines, "\n")
end

local function ApplyGating()
   local locked = BP.Bot.disabled and true or false
   local why = locked and "AutoTravel ist geladen und steuert den Playerbot - hier gesperrt." or nil

   for _, w in ipairs(gated) do
      if w.SetAlpha then w:SetAlpha(locked and 0.45 or 1) end
      if w.Enable and w.Disable then
         if locked then w:Disable() else w:Enable() end
      end
      w.gatedNote = why
   end

   -- Nur ein Hinweis, kein Sperren: die Botbefehle verbirgt Botpad weiter, die
   -- [AT]-Zeilen entscheidet dann AutoTravel.
   if O.hideBox then
      O.hideBox.gatedNote = BP.autoTravel
         and "AutoTravel ist geladen: ob die [AT]-Zeilen verborgen werden, bestimmt dessen Einstellung " ..
             "(Protokollzeilen im Chat zeigen). Hier gilt der Haken nur fuer die Botbefehle."
         or nil
   end
end

local function RefreshModes()
   local cur = BP.Get("Mode")
   for _, b in ipairs(modeButtons) do
      BP.UI.SetSelected(b, b.modeKey == cur)
   end
end

-- ---------------------------------------------------------------------------
-- Seite
-- ---------------------------------------------------------------------------

local function Build()
   if frame then return frame end

   frame = CreateFrame("Frame", "BotpadOptionsPanel", UIParent)
   frame.name = "Botpad"

   local sf = CreateFrame("ScrollFrame", "BotpadOptionsScroll", frame, "UIPanelScrollFrameTemplate")
   sf:SetPoint("TOPLEFT", 0, -4)
   sf:SetPoint("BOTTOMRIGHT", -28, 4)
   sf:EnableMouseWheel(true)
   sf:SetScript("OnMouseWheel", function(self, delta)
      local bar = _G["BotpadOptionsScrollScrollBar"]
      if bar then bar:SetValue(bar:GetValue() - delta * 40) end
   end)

   content = CreateFrame("Frame", "BotpadOptionsContent", sf)
   content:SetWidth(WIDTH)
   content:SetHeight(10)          -- wird am Ende auf die tatsaechliche Hoehe gesetzt
   sf:SetScrollChild(content)

   local c = content
   local y = -12
   local function Advance(h) y = y - h end

   local title = c:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
   title:SetPoint("TOPLEFT", 16, y)
   title:SetText("Botpad")
   Advance(24)

   O.status = c:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
   O.status:SetPoint("TOPLEFT", 16, y)
   O.status:SetWidth(WIDTH - 32)
   O.status:SetJustifyH("LEFT")
   Advance(46)

   -- Nur wenn AutoTravel beim Anmelden da war (BP.autoTravel steht dann schon fest).
   if BP.autoTravel then
      O.autoNote = Note(c, "AutoTravel ist ebenfalls geladen und steuert den Playerbot. Botpad setzt deshalb " ..
                           "keine Strategien (Modus, Zuruecksetzen) und zeigt die Meldungen des Servermoduls " ..
                           "nicht noch einmal an; Teleport und Umschalter bleiben nutzbar. Die Einstellungen " ..
                           "dazu stehen unter AutoTravel.", 16, y)
      O.autoNote:SetTextColor(0.91, 0.65, 0.29)
      Advance(46)
   end

   -- ---- Bedienfeld ---------------------------------------------------------
   Header(c, "Bedienfeld", 16, y)
   Advance(28)

   Check(c, "Bedienfeld anzeigen", "Das kleine Fenster mit Statuspunkt, Modus und Knoepfen.",
         16, y, "Shown", function() BP.UI.Refresh() end)
   Advance(26)

   Check(c, "Minimap-Knopf anzeigen",
         "Linksklick: Bot an/aus. Rechtsklick: Fenster. Umschalt+Klick: diese Seite.",
         16, y, "MinimapButton", function() BP.UI.Refresh() end)
   Advance(34)

   -- ---- Playerbot ----------------------------------------------------------
   Header(c, "Playerbot-Selbstmodus", 16, y)
   Advance(28)

   local lbl = c:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
   lbl:SetPoint("TOPLEFT", 20, y)
   lbl:SetText("Modus beim Einschalten:")
   Advance(18)

   for i, m in ipairs(BP.Bot.Modes) do
      local col = (i - 1) % 3
      local row = math.floor((i - 1) / 3)
      local b = BP.UI.Button(c, 118, 22, m.name, function()
         BP.Bot.SetMode(m.key)             -- unter AutoTravel lehnt es selbst ab
      end)
      b:SetPoint("TOPLEFT", 20 + col * 126, y - row * 26)
      b.modeKey = m.key
      b.tip = function()
         GameTooltip:AddLine(m.name)
         GameTooltip:AddLine(m.desc, 0.7, 0.7, 0.7, true)
         if BP.Bot.disabled then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("AutoTravel ist geladen und steuert den Playerbot - hier gesperrt.",
                                0.91, 0.65, 0.29, true)
         end
      end
      table.insert(modeButtons, b)
      table.insert(gated, b)
   end
   Advance(math.ceil(#BP.Bot.Modes / 3) * 26 + 6)

   local reset = Check(c, "Strategien beim Ausschalten zuruecksetzen",
         "Setzt vor dem Ausschalten 'nc !', 'co !' und 'll normal', damit der Charakter nicht mit halb " ..
         "gesetzten Botstrategien zurueckbleibt.",
         16, y, "ResetOnStop")
   table.insert(gated, reset)
   Advance(26)

   O.hideBox = Check(c, "Eigene Botbefehle und Protokollzeilen im Chat verbergen",
         "Blendet die Fluesterbefehle an den eigenen Charakter und die [AT]-Zeilen des Servermoduls aus. " ..
         "Zum Fehlersuchen ausschalten.",
         16, y, "HideCommands")
   Advance(34)

   local cmd = Edit(c, "Umschaltbefehl fuer den Selbstmodus (Enter speichert)", 20, y, 300,
      function() return BP.Get("SelfCommand") end,
      function(text)
         if text == "" then
            BP.Set("SelfCommand", BP.DEFAULTS.SelfCommand)
            BP.Print("Umschaltbefehl: " .. BP.DEFAULTS.SelfCommand)
         elseif not BP.IsServerCommand(text) then
            BP.Warn(BP.NOT_A_COMMAND)
         else
            BP.Set("SelfCommand", text)
            BP.Print("Umschaltbefehl: " .. text)
         end
      end)
   local cmdDefault = BP.UI.Button(c, 100, 22, "Standard", function()
      BP.Set("SelfCommand", BP.DEFAULTS.SelfCommand)
      cmd.Load()
   end)
   cmdDefault:SetPoint("TOPLEFT", 332, y - 14)
   Advance(44)

   Note(c, "'.playerbots bot self' ist ein Umschalter: derselbe Befehl schaltet ein und aus. " ..
           "Die Schreibweise mit '.playerbots help' pruefen.", 20, y)
   Advance(34)

   -- ---- Teleport -----------------------------------------------------------
   Header(c, "Teleport zum Carbonite-Ziel", 16, y)
   Advance(28)

   Check(c, "Vor dem Teleport nachfragen",
         "Zeigt eine Sicherheitsabfrage mit dem Namen des Ziels.", 16, y, "ConfirmTp")
   Advance(34)

   Edit(c, "Karten-ID erzwingen (leer oder 0 = automatisch; Enter speichert)", 20, y, 120,
      function()
         local id = BP.Get("ForcedMapId")
         return id and tostring(id) or ""
      end,
      function(text)
         if text == "" or text == "0" then
            BP.Set("ForcedMapId", nil)
            BP.Print("Karten-ID wieder automatisch.")
         elseif string.match(text, "^%d+$") and tonumber(text) <= 99999 then
            BP.Set("ForcedMapId", tonumber(text))
            BP.Print("Karten-ID erzwungen: " .. tonumber(text))
         else
            -- Kein stilles Loeschen: "1 2" oder "abc" ist ein Tippfehler, keine Absicht
            BP.Warn("Keine gueltige Karten-ID: '" .. text .. "' (eine ganze Zahl; leer oder 0 = automatisch).")
         end
      end)
   Advance(44)

   local tp = BP.UI.Button(c, 190, 22, "Jetzt zum Ziel teleportieren", function() BP.Teleport() end)
   tp:SetPoint("TOPLEFT", 20, y)
   tp.tip = function()
      GameTooltip:AddLine("Teleport zum Carbonite-Ziel")
      GameTooltip:AddLine("Braucht das Servermodul mod-autotravel.", 0.7, 0.7, 0.7, true)
   end
   Advance(40)

   -- ---- Diagnose -----------------------------------------------------------
   Header(c, "Diagnose", 16, y)
   Advance(28)

   Check(c, "Gesendete Befehle anzeigen (Debug)",
         "Gibt jeden Befehl, den Botpad an den Server oder den Bot schickt, im Chat aus.",
         16, y, "Debug")
   Advance(34)

   local all = BP.UI.Button(c, 220, 22, "Alle Einstellungen zuruecksetzen", function() O.ResetAll() end)
   all:SetPoint("TOPLEFT", 20, y)
   all.tip = function()
      GameTooltip:AddLine("Alle Einstellungen zuruecksetzen")
      GameTooltip:AddLine("Setzt Modus, Umschaltbefehl, Karten-ID und die Haken (auch den fuer den " ..
                          "Minimap-Knopf) auf die Voreinstellung. Fensterposition, Knopfwinkel und ob " ..
                          "das Fenster angezeigt wird bleiben.", 0.7, 0.7, 0.7, true)
   end
   Advance(36)

   content:SetHeight(-y + 10)

   frame.refresh = function() O.Load() end
   frame.okay    = function() end
   frame.cancel  = function() end
   frame.default = function() O.ResetAll() end       -- "Standard" im Optionsfenster
   frame:SetScript("OnShow", function() O.Load() end)

   if InterfaceOptions_AddCategory then
      InterfaceOptions_AddCategory(frame)
   end
   return frame
end

-- ---------------------------------------------------------------------------
-- Laden und Oeffnen
-- ---------------------------------------------------------------------------

function O.Load()
   if not frame then return end
   for _, w in ipairs(widgets) do
      if w.Load then w.Load() end
   end
   RefreshModes()
   ApplyGating()
   if O.status then O.status:SetText(StatusText()) end
end

function O.ResetAll()
   BP.ResetSettings()
   BP.Print("Einstellungen auf die Voreinstellung zurueckgesetzt.")
   if BP.UI then BP.UI.Refresh() BP.UI.Update() end
   O.Load()
end

-- Von Befehlen und Fenster aus aufrufbar, auch bevor die Seite gebaut ist.
O.Refresh = O.Load

function O.Open()
   Build()
   O.Load()
   if InterfaceOptionsFrame_OpenToCategory then
      InterfaceOptionsFrame_OpenToCategory(frame)
      InterfaceOptionsFrame_OpenToCategory(frame)   -- 3.3.5a braucht zwei Aufrufe
   end
end

function O.Init()
   Build()
   O.Load()
end

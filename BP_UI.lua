-- BP_UI.lua
-- ---------------------------------------------------------------------------
-- Minimales Bedienfeld: Statuspunkt, Modusauswahl, zwei Knoepfe.
-- Gebaut nur aus Bordmitteln (Backdrop + WHITE8X8), damit keine Grafikdateien
-- mitgeliefert werden muessen.
-- ---------------------------------------------------------------------------

local BP = Botpad
BP.UI = {}
local UI = BP.UI

local WHITE = "Interface\\Buttons\\WHITE8X8"

local COL = {
   bg     = { 0.055, 0.062, 0.075, 0.95 },
   border = { 0.22,  0.25,  0.30,  1 },
   accent = { 0.35,  0.69,  0.91,  1 },
}

local panel, mini, dropdown

-- ---------------------------------------------------------------------------

local function Skin(f, bg, border)
   f:SetBackdrop({
      bgFile = WHITE, edgeFile = WHITE, tile = false, edgeSize = 1,
      insets = { left = 1, right = 1, top = 1, bottom = 1 },
   })
   bg = bg or COL.bg
   border = border or COL.border
   f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
   f:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end

local function Button(parent, w, h, label, onClick)
   local b = CreateFrame("Button", nil, parent)
   b:SetWidth(w) b:SetHeight(h)
   Skin(b, { 0.13, 0.15, 0.18, 1 }, { 0.26, 0.29, 0.34, 1 })

   local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
   fs:SetPoint("CENTER")
   fs:SetText(label)
   b.label = fs

   b:SetScript("OnEnter", function()
      b:SetBackdropColor(0.19, 0.22, 0.27, 1)
      b:SetBackdropBorderColor(COL.accent[1], COL.accent[2], COL.accent[3], 1)
      if b.tip then
         GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
         b.tip()
         GameTooltip:Show()
      end
   end)
   b:SetScript("OnLeave", function()
      b:SetBackdropColor(0.13, 0.15, 0.18, 1)
      b:SetBackdropBorderColor(0.26, 0.29, 0.34, 1)
      GameTooltip:Hide()
   end)
   b:SetScript("OnClick", onClick)
   return b
end

-- ---------------------------------------------------------------------------
-- Panel
-- ---------------------------------------------------------------------------

local function BuildPanel()
   if panel then return end

   local f = CreateFrame("Frame", "BotpadPanel", UIParent)
   f:SetWidth(186)
   f:SetHeight(90)
   Skin(f)
   f:SetMovable(true)
   f:EnableMouse(true)
   f:RegisterForDrag("LeftButton")
   f:SetScript("OnDragStart", function() f:StartMoving() end)
   f:SetScript("OnDragStop", function()
      f:StopMovingOrSizing()
      local p, _, _, x, y = f:GetPoint()
      BP.Set("Point", { p, x, y })
   end)
   f:SetClampedToScreen(true)

   local p = BP.Get("Point") or { "CENTER", 260, 0 }
   f:SetPoint(p[1] or "CENTER", UIParent, p[1] or "CENTER", p[2] or 0, p[3] or 0)

   -- Kopfzeile
   local head = CreateFrame("Frame", nil, f)
   head:SetPoint("TOPLEFT", 1, -1)
   head:SetPoint("TOPRIGHT", -1, -1)
   head:SetHeight(22)
   head:SetBackdrop({ bgFile = WHITE })
   head:SetBackdropColor(0.10, 0.12, 0.15, 1)

   local stripe = head:CreateTexture(nil, "OVERLAY")
   stripe:SetTexture(WHITE)
   stripe:SetVertexColor(COL.accent[1], COL.accent[2], COL.accent[3], 1)
   stripe:SetPoint("TOPLEFT") stripe:SetPoint("BOTTOMLEFT")
   stripe:SetWidth(3)

   local title = head:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
   title:SetPoint("LEFT", 10, 0)
   title:SetText("Botpad")
   title:SetTextColor(0.92, 0.94, 0.97)

   local close = Button(head, 16, 14, "|cffaaaaaax|r", function()
      BP.Set("Shown", 0)
      f:Hide()
   end)
   close:SetPoint("RIGHT", -4, 0)

   -- Zustandszeile
   local dot = f:CreateTexture(nil, "OVERLAY")
   dot:SetTexture(WHITE)
   dot:SetWidth(6) dot:SetHeight(6)
   dot:SetPoint("TOPLEFT", 12, -40)
   f.dot = dot

   local st = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
   st:SetPoint("LEFT", dot, "RIGHT", 7, 0)
   f.lState = st

   -- Modusauswahl
   local dropdown = CreateFrame("Frame", "BotpadModeDropDown", f, "UIDropDownMenuTemplate")
   dropdown:SetPoint("TOPLEFT", 54, -28)
   dropdown:SetWidth(30)

   -- In 3.3.5a lautet die Reihenfolge (frame, width). Aeltere Fassungen
   -- erwarten (width, frame) -- deshalb abgesichert.
   if not pcall(UIDropDownMenu_SetWidth, dropdown, 80) then
      pcall(UIDropDownMenu_SetWidth, 80, dropdown)
   end

   UIDropDownMenu_Initialize(dropdown, function()
      for _, m in ipairs(BP.Bot.Modes) do
         local info = UIDropDownMenu_CreateInfo()
         info.text = m.name
         info.value = m.key
         info.checked = (m.key == BP.Get("Mode"))
         info.func = function()
            BP.Bot.SetMode(m.key)
            UIDropDownMenu_SetSelectedValue(dropdown, m.key)
         end
         UIDropDownMenu_AddButton(info)
      end
   end)
   UIDropDownMenu_SetSelectedValue(dropdown, BP.Get("Mode"))

   -- Aktionen
   local bot = Button(f, 80, 24, "", function() BP.ToggleBot() end)
   bot:SetPoint("TOPLEFT", 12, -58)
   bot.label:SetFontObject("GameFontNormal")
   bot.tip = function()
      GameTooltip:AddLine("Playerbot-Selbstmodus")
      GameTooltip:AddLine("Schaltet ihn ein oder aus und setzt", 0.7, 0.7, 0.7)
      GameTooltip:AddLine("beim Einschalten den gewaehlten Modus.", 0.7, 0.7, 0.7)
   end
   f.bot = bot

   local tp = Button(f, 80, 24, "|cffe8c44aTeleport|r", function() BP.Teleport() end)
   tp:SetPoint("TOPLEFT", 92, -58)
   tp.tip = function()
      GameTooltip:AddLine("Teleport zum Carbonite-Ziel")
      GameTooltip:AddLine("Braucht das Servermodul mod-autotravel:", 0.7, 0.7, 0.7)
      GameTooltip:AddLine("nur dort laesst sich die Hoehe bestimmen.", 0.7, 0.7, 0.7)
   end

   panel = f
   UI.Refresh()
end

-- ---------------------------------------------------------------------------
-- Minimap-Knopf
-- ---------------------------------------------------------------------------

local function PositionMinimap()
   if not mini then return end
   local a = BP.Get("MinimapAngle") or 210
   local rad = math.rad(a)
   mini:SetPoint("CENTER", Minimap, "CENTER", 78 * math.cos(rad), 78 * math.sin(rad))
end

local function BuildMinimap()
   if mini then return end

   local b = CreateFrame("Button", "BotpadMinimapButton", Minimap)
   b:SetWidth(31) b:SetHeight(31)
   b:SetFrameStrata("MEDIUM")
   b:SetFrameLevel(8)
   b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
   b:RegisterForDrag("LeftButton")
   b:SetMovable(true)

   local overlay = b:CreateTexture(nil, "OVERLAY")
   overlay:SetWidth(53) overlay:SetHeight(53)
   overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
   overlay:SetPoint("TOPLEFT")

   local icon = b:CreateTexture(nil, "BACKGROUND")
   icon:SetWidth(20) icon:SetHeight(20)
   icon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
   icon:SetPoint("TOPLEFT", 7, -6)
   icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
   b.icon = icon

   b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

   b:SetScript("OnClick", function(self, button)
      if button == "RightButton" then UI.Toggle() else BP.ToggleBot() end
   end)

   b:SetScript("OnEnter", function()
      GameTooltip:SetOwner(b, "ANCHOR_LEFT")
      GameTooltip:AddLine("Botpad")
      GameTooltip:AddLine("Bot: " .. string.gsub(BP.Bot.StatusText(),
                          "|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""), 1, 1, 1)
      GameTooltip:AddLine("Modus: " .. BP.Bot.Current().name, 1, 1, 1)
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("Linksklick: Bot an/aus", 0.33, 0.82, 0.48)
      GameTooltip:AddLine("Rechtsklick: Fenster zeigen", 0.35, 0.69, 0.91)
      GameTooltip:AddLine("Ziehen: Knopf verschieben", 0.6, 0.6, 0.6)
      GameTooltip:Show()
   end)
   b:SetScript("OnLeave", function() GameTooltip:Hide() end)

   b:SetScript("OnDragStart", function() b.dragging = true end)
   b:SetScript("OnDragStop", function() b.dragging = false end)
   b:SetScript("OnUpdate", function()
      if not b.dragging then return end
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local scale = UIParent:GetEffectiveScale()
      cx, cy = cx / scale, cy / scale
      BP.Set("MinimapAngle", math.deg(math.atan2(cy - my, cx - mx)))
      PositionMinimap()
   end)

   mini = b
   PositionMinimap()
end

-- ---------------------------------------------------------------------------

function UI.Build()
   BuildPanel()
   BuildMinimap()
   UI.Update()
end

function UI.Refresh()
   if not panel then return end
   if BP.GetBool("Shown") then panel:Show() else panel:Hide() end
end

function UI.Toggle()
   BP.Set("Shown", BP.GetBool("Shown") and 0 or 1)
   UI.Refresh()
end

function UI.Update()
   local on = (BP.Bot.running == true)

   if mini and mini.icon then
      if on then mini.icon:SetVertexColor(0.4, 1, 0.5)
      elseif BP.Bot.running == false then mini.icon:SetVertexColor(1, 1, 1)
      else mini.icon:SetVertexColor(1, 0.85, 0.4) end
   end

   if not panel then return end

   if on then panel.dot:SetVertexColor(0.33, 0.82, 0.48, 1)
   elseif BP.Bot.running == false then panel.dot:SetVertexColor(0.35, 0.38, 0.44, 1)
   else panel.dot:SetVertexColor(0.91, 0.77, 0.29, 1) end

   panel.lState:SetText("Bot " .. BP.Bot.StatusText())
   panel.bot.label:SetText(on and "BOT AUS" or "BOT EIN")

   if dropdown then
      UIDropDownMenu_SetSelectedValue(dropdown, BP.Get("Mode"))
      if UIDropDownMenu_SetText then
         pcall(UIDropDownMenu_SetText, dropdown, BP.Bot.Current().name)
      end
   end
end

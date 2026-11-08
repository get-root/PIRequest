-- PIRequest — Options.lua
-- Panneau d'options (Échap > Options > AddOns > PIRequest, ou /pirequest config) :
--   * activer / son / tracker
--   * filtre OPTIONNEL par nom de personnage
--   * choix des CDs offensifs (par classe) + IDs personnalisés

local panel = CreateFrame("Frame")
panel.name = "PIRequest"

local category
if Settings and Settings.RegisterCanvasLayoutCategory then
    category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
end

function PIReq_OpenOptions()
    if category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
    else
        PIReq.Print("Panneau d'options indisponible sur ce client.")
    end
end

local built = false
local refreshers = {}   -- fonctions rappelées par PIReq.RefreshOptions

function PIReq.RefreshOptions()
    for _, fn in ipairs(refreshers) do fn() end
end

local function SpellLabel(id)
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    return name or ("Sort #" .. id)
end

local function SpellIcon(id)
    return C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
end

local function ClassTitle(class)
    if class == "POTION" then return "Potions de burst" end
    local name = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return string.format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, name) end
    return name
end

-- ---------------------------------------------------------------------------
-- Sélecteur de son : recherche dans tout le catalogue
-- ---------------------------------------------------------------------------

local ROWS = 12
local picker

local function CurrentSoundLabel()
    local db = PIReq.DB
    if db.soundKey == "custom" then
        return db.soundName or ("FileDataID " .. tostring(db.soundCustom))
    end
    for _, s in ipairs(PIReq.SOUNDS) do
        if s.key == db.soundKey then return s.label end
    end
    return PIReq.SOUNDS[1].label
end

local function OpenSoundPicker()
    if picker then picker:Show() return end
    local cat = PIReq.SOUND_CATALOG
    local lower = {}
    for i, e in ipairs(cat) do lower[i] = e[2]:lower() end

    local f = CreateFrame("Frame", "PIReqSoundPicker", UIParent, "BackdropTemplate")
    picker = f
    f:SetSize(460, 40 + ROWS * 22 + 70)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                    tile = true, tileSize = 32, edgeSize = 32,
                    insets = { left = 8, right = 8, top = 8, bottom = 8 } })

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("Choisir un son (" .. #cat .. " sons du jeu)")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    search:SetPoint("TOPLEFT", 24, -44)
    search:SetSize(400, 22)
    search:SetAutoFocus(false)

    local filtered, page = {}, 1
    local rows = {}
    local info = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    info:SetPoint("BOTTOM", 0, 20)

    local function Refilter()
        wipe(filtered)
        local terms = {}
        for t in (search:GetText() or ""):lower():gmatch("%S+") do terms[#terms + 1] = t end
        for i = 1, #cat do
            local ok = true
            for _, t in ipairs(terms) do
                if not lower[i]:find(t, 1, true) then ok = false break end
            end
            if ok then filtered[#filtered + 1] = i end
        end
        page = 1
    end

    local function Render()
        local pages = math.max(1, math.ceil(#filtered / ROWS))
        if page > pages then page = pages end
        if page < 1 then page = 1 end
        local db = PIReq.DB
        for r = 1, ROWS do
            local idx = filtered[(page - 1) * ROWS + r]
            local row = rows[r]
            if idx then
                local e = cat[idx]
                row.entry = e
                row.text:SetText(e[2])
                row.sel:SetShown(db.soundKey == "custom" and db.soundCustom == e[1])
                row:Show()
            else
                row.entry = nil
                row:Hide()
            end
        end
        info:SetText(string.format("%d résultat(s) — page %d/%d — clic = écouter et choisir", #filtered, page, pages))
    end

    for r = 1, ROWS do
        local row = CreateFrame("Button", nil, f)
        row:SetSize(420, 20)
        row:SetPoint("TOPLEFT", 24, -74 - (r - 1) * 22)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.sel = row:CreateTexture(nil, "BACKGROUND")
        row.sel:SetAllPoints()
        row.sel:SetColorTexture(1, 0.84, 0, 0.25)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.text:SetPoint("LEFT", 4, 0)
        row.text:SetPoint("RIGHT", -4, 0)
        row.text:SetJustifyH("LEFT")
        row:SetScript("OnClick", function(self)
            local e = self.entry
            if not e then return end
            local db = PIReq.DB
            db.soundKey, db.soundCustom, db.soundName = "custom", e[1], e[2]
            PIReq.PlayAlertSound()
            PIReq.Refresh()          -- ré-enregistre les sons moteur avec ce FileDataID
            PIReq.RefreshOptions()
            Render()
        end)
        rows[r] = row
    end

    local prev = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    prev:SetSize(70, 22); prev:SetPoint("BOTTOMLEFT", 24, 16); prev:SetText("< Préc.")
    prev:SetScript("OnClick", function() page = page - 1; Render() end)
    local nxt = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    nxt:SetSize(70, 22); nxt:SetPoint("BOTTOMRIGHT", -24, 16); nxt:SetText("Suiv. >")
    nxt:SetScript("OnClick", function() page = page + 1; Render() end)

    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta) page = page - delta; Render() end)

    search:SetScript("OnTextChanged", function() Refilter(); Render() end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    tinsert(UISpecialFrames, "PIReqSoundPicker") -- Échap ferme
    Refilter(); Render()
end

local function Build()
    if built then return end
    built = true
    local db = PIReq.DB

    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(580, 10)
    scroll:SetScrollChild(content)

    local y = -4
    local function Text(template, str, x, yy, parent)
        local fs = (parent or content):CreateFontString(nil, "OVERLAY", template)
        fs:SetPoint("TOPLEFT", x or 8, yy or y)
        fs:SetJustifyH("LEFT")
        fs:SetText(str)
        return fs
    end

    local function Checkbox(label, x, yy, get, set)
        local cb = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", x, yy)
        cb:SetSize(26, 26)
        local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        fs:SetText(label)
        cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
        refreshers[#refreshers + 1] = function() cb:SetChecked(get()) end
        return cb, fs
    end

    local function Button(label, x, yy, w, onClick)
        local b = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        b:SetPoint("TOPLEFT", x, yy)
        b:SetSize(w, 22)
        b:SetText(label)
        b:SetScript("OnClick", onClick)
        return b
    end

    local function EditBox(x, yy, w, onCommit)
        local eb = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
        eb:SetPoint("TOPLEFT", x, yy)
        eb:SetSize(w, 22)
        eb:SetAutoFocus(false)
        eb:SetScript("OnEnterPressed", function(self) onCommit(self:GetText()); self:ClearFocus() end)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); PIReq.RefreshOptions() end)
        return eb
    end

    -- Général ---------------------------------------------------------------
    Text("GameFontNormalLarge", "PIRequest — alertes CD offensifs", 8, y); y = y - 30

    Checkbox("Alertes activées", 8, y, function() return db.enabled end,
        function(v) db.enabled = v; PIReq.Refresh() end); y = y - 26
    Checkbox("Son d'alerte", 8, y, function() return db.sound end,
        function(v) db.sound = v; PIReq.Refresh() end); y = y - 26
    Checkbox("Icônes de CD en combat / donjon (tracker déplaçable)", 8, y, function() return db.tracker end,
        function(v) db.tracker = v; PIReq.Refresh() end)
    Button("Déplacer le tracker", 380, y - 2, 150, function() PIReq_ToggleTrackerUnlock() end)
    y = y - 36

    -- Choix du son ----------------------------------------------------------
    Text("GameFontNormal", "Son d'alerte", 8, y)
    Button("Écouter", 120, y + 4, 80, function() PIReq.PlayAlertSound() end)
    Button("Tous les sons…", 206, y + 4, 130, OpenSoundPicker)
    local current = Text("GameFontHighlightSmall", "", 346, y - 4)
    current:SetWidth(230)
    refreshers[#refreshers + 1] = function() current:SetText("Actuel : " .. CurrentSoundLabel()) end
    y = y - 26
    for i, snd in ipairs(PIReq.SOUNDS) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        Checkbox(snd.label, 8 + col * 280, y - row * 24,
            function() return db.soundKey == snd.key end,
            function()
                db.soundKey = snd.key
                db.soundName = nil
                PIReq.PlayAlertSound()           -- aperçu
                PIReq.Refresh()                  -- ré-enregistre les sons moteur
                PIReq.RefreshOptions()
            end)
    end
    y = y - math.ceil(#PIReq.SOUNDS / 2) * 24 - 4
    Checkbox("Personnalisé (FileDataID) :", 8, y,
        function() return db.soundKey == "custom" end,
        function(v)
            if v and tonumber(db.soundCustom) then
                db.soundKey = "custom"; PIReq.PlayAlertSound(); PIReq.Refresh()
            end
            PIReq.RefreshOptions()
        end)
    local customSound = EditBox(240, y - 2, 110, function(text)
        local n = tonumber(text)
        if n then
            db.soundCustom = n; db.soundKey = "custom"
            PIReq.PlayAlertSound(); PIReq.Refresh()
        end
        PIReq.RefreshOptions()
    end)
    customSound:SetNumeric(true)
    refreshers[#refreshers + 1] = function() customSound:SetText(db.soundCustom and tostring(db.soundCustom) or "") end
    y = y - 26
    Text("GameFontDisableSmall", "Entrée pour valider. Les FileDataID se trouvent sur wago.tools/files (sons .ogg/.mp3).", 16, y)
    y = y - 30

    -- Filtre par nom --------------------------------------------------------
    Text("GameFontNormal", "Filtre par personnage (optionnel)", 8, y); y = y - 22
    Checkbox("Ne m'alerter que pour ces personnages :", 8, y, function() return db.filterByName end,
        function(v) db.filterByName = v; PIReq.ApplyConfig() end); y = y - 28

    local namesBox = EditBox(16, y, 360, function(text)
        db.names = PIReq.ParseNames(text)
        if #db.names == 0 then db.filterByName = false end
        PIReq.ApplyConfig(); PIReq.RefreshOptions()
    end)
    refreshers[#refreshers + 1] = function() namesBox:SetText(table.concat(db.names, ", ")); namesBox:SetCursorPosition(0) end
    Button("Ajouter ma cible", 390, y, 140, function()
        if UnitExists("target") and UnitIsPlayer("target") then
            local n = PIReq.UnitShortName("target")
            if n then
                local already = false
                for _, v in ipairs(db.names) do if v:lower() == n:lower() then already = true end end
                if not already then db.names[#db.names + 1] = n end
                db.filterByName = true
                PIReq.ApplyConfig(); PIReq.RefreshOptions()
            end
        else
            PIReq.Print("Cible un joueur d'abord.")
        end
    end)
    y = y - 26
    Text("GameFontDisableSmall", "Noms séparés par des virgules/espaces (sans royaume). Si le filtre est actif, le rôle (tank/heal) est ignoré.", 16, y)
    y = y - 28

    -- IDs personnalisés -----------------------------------------------------
    Text("GameFontNormal", "ID de sort personnalisé", 8, y); y = y - 22
    local idBox = EditBox(16, y, 120, function() end)
    idBox:SetNumeric(true)
    local customList
    Button("Ajouter", 146, y, 80, function()
        local id = tonumber(idBox:GetText())
        if id then db.custom[id] = true; idBox:SetText(""); PIReq.ApplyConfig(); PIReq.RefreshOptions() end
    end)
    Button("Retirer", 232, y, 80, function()
        local id = tonumber(idBox:GetText())
        if id then db.custom[id] = nil; idBox:SetText(""); PIReq.ApplyConfig(); PIReq.RefreshOptions() end
    end)
    y = y - 26
    customList = Text("GameFontHighlightSmall", "", 16, y)
    customList:SetWidth(540)
    refreshers[#refreshers + 1] = function()
        local parts = {}
        for id in pairs(db.custom) do parts[#parts + 1] = id .. " (" .. SpellLabel(id) .. ")" end
        table.sort(parts)
        customList:SetText(#parts > 0 and ("Ajoutés : " .. table.concat(parts, ", ")) or "Aucun ID personnalisé.")
    end
    y = y - 30

    -- CDs par classe --------------------------------------------------------
    Checkbox("★ CDs prioritaires uniquement (~2 min)", 8, y, function() return db.priorityOnly end,
        function(v) db.priorityOnly = v; PIReq.ApplyConfig() end); y = y - 30
    Text("GameFontNormal", "CDs offensifs qui déclenchent l'alerte", 8, y)
    Button("Tout cocher", 300, y + 4, 110, function()
        for _, e in ipairs(PIReq.SPELLS) do db.spells[e.id] = true end
        PIReq.ApplyConfig(); PIReq.RefreshOptions()
    end)
    Button("Valeurs par défaut", 416, y + 4, 130, function()
        wipe(db.spells); PIReq.ApplyConfig(); PIReq.RefreshOptions()
    end)
    y = y - 30

    local COL_W = 280
    for _, class in ipairs(PIReq.CLASS_ORDER) do
        local entries = {}
        for _, e in ipairs(PIReq.SPELLS) do
            if e.class == class then entries[#entries + 1] = e end
        end
        table.sort(entries, function(a, b)
            if (a.priority and 1 or 0) ~= (b.priority and 1 or 0) then return a.priority end
            return a.id < b.id
        end)
        if #entries > 0 then
            Text("GameFontNormal", ClassTitle(class), 8, y)
            Button("Aucun", 210, y + 3, 60, function()
                for _, e in ipairs(entries) do db.spells[e.id] = false end
                PIReq.ApplyConfig(); PIReq.RefreshOptions()
            end)
            Button("Tous", 274, y + 3, 60, function()
                for _, e in ipairs(entries) do db.spells[e.id] = true end
                PIReq.ApplyConfig(); PIReq.RefreshOptions()
            end)
            y = y - 26

            for i, e in ipairs(entries) do
                local col = (i - 1) % 2
                local row = math.floor((i - 1) / 2)
                local cb, fs = Checkbox("", 8 + col * COL_W, y - row * 24,
                    function() return PIReq.IsEntryEnabled(e) end,
                    function(v) db.spells[e.id] = v; PIReq.ApplyConfig() end)
                local icon = cb:CreateTexture(nil, "ARTWORK")
                icon:SetSize(18, 18)
                icon:SetPoint("LEFT", cb, "RIGHT", 2, 0)
                fs:ClearAllPoints()
                fs:SetPoint("LEFT", icon, "RIGHT", 4, 0)
                refreshers[#refreshers + 1] = function()
                    icon:SetTexture(SpellIcon(e.id))
                    fs:SetText((e.priority and "|cffffd700★|r " or "") .. SpellLabel(e.id))
                end
            end
            y = y - math.ceil(#entries / 2) * 24 - 10
        end
    end

    content:SetHeight(-y + 20)
    PIReq.RefreshOptions()
end

panel:SetScript("OnShow", function()
    if not PIReq.DB then return end
    Build()
    PIReq.RefreshOptions() -- noms de sorts potentiellement chargés entre-temps
end)

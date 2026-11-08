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

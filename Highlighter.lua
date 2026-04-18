-- PIRequest — Highlighter.lua
-- Côté prêtre : highlight de la barre de vie du DPS demandeur.

local HIGHLIGHT_DURATION = 15   -- secondes avant suppression automatique
local PULSE_MIN          = 0.4
local PULSE_MAX          = 1.0
local PULSE_SPEED        = 2.0  -- cycles par seconde
local NOTIF_DURATION     = 5    -- secondes pour la notification aura
local PI_SPELL_ID        = 10060

local activeHighlights = {}  -- [unitToken] = { overlay, startTime, ticker }

-- ---------------------------------------------------------------------------
-- Notification aura (icône PI + nom du joueur)
-- Définie AVANT PIReq_Highlight pour être dans sa portée lexicale.
-- ---------------------------------------------------------------------------

local notifFrame = nil
local notifTimer  = nil

local function GetNotifFrame()
    if notifFrame then return notifFrame end

    local f = CreateFrame("Frame", "PIReqNotifFrame", UIParent)
    f:SetSize(260, 80)
    f:SetPoint("TOP", UIParent, "TOP", 0, -220)
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)

    -- Fond semi-transparent
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetColorTexture(0, 0, 0, 0.88)

    -- Bordure dorée (4 textures)
    local B = 2
    local function MakeBorder(p1, p2, x1, y1, x2, y2)
        local t = f:CreateTexture(nil, "BORDER")
        t:SetColorTexture(1, 0.84, 0, 1)
        t:SetPoint(p1, f, p1, x1, y1)
        t:SetPoint(p2, f, p2, x2, y2)
    end
    MakeBorder("TOPLEFT",    "TOPRIGHT",    0,  0,  0,  -B)
    MakeBorder("BOTTOMLEFT", "BOTTOMRIGHT", 0,  B,  0,   0)
    MakeBorder("TOPLEFT",    "BOTTOMLEFT",  0, -B,  B,   B)
    MakeBorder("TOPRIGHT",   "BOTTOMRIGHT",-B, -B,  0,   B)

    -- Icône Power Infusion
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(56, 56)
    icon:SetPoint("LEFT", f, "LEFT", 12, 0)
    local spellTex = (C_Spell and C_Spell.GetSpellTexture)
                     and C_Spell.GetSpellTexture(PI_SPELL_ID)
                     or  (GetSpellTexture and GetSpellTexture(PI_SPELL_ID))
    if spellTex then
        icon:SetTexture(spellTex)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    f.icon = icon

    -- Nom du joueur
    local nameText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    nameText:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -6)
    nameText:SetPoint("RIGHT",   f,    "RIGHT",   -10,  0)
    nameText:SetJustifyH("LEFT")
    nameText:SetTextColor(1, 1, 1, 1)
    f.nameText = nameText

    -- Sous-titre
    local subText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -4)
    subText:SetPoint("RIGHT",   f,        "RIGHT",     -10, 0)
    subText:SetJustifyH("LEFT")
    subText:SetTextColor(1, 0.84, 0, 1)
    subText:SetText("veut une Power Infusion !")

    f:Hide()
    notifFrame = f
    return f
end

local function ShowNotification(playerName)
    local ok, err = pcall(function()
        local f = GetNotifFrame()
        f.nameText:SetText(playerName)
        f:SetAlpha(1)
        f:Show()

        if notifTimer then notifTimer:Cancel() end
        notifTimer = C_Timer.NewTimer(NOTIF_DURATION, function()
            f:Hide()
            notifTimer = nil
        end)
    end)
    if not ok then
        print("|cffff6600[PIRequest]|r Erreur notification : " .. tostring(err))
    end
end

-- ---------------------------------------------------------------------------
-- Raid frame highlight
-- ---------------------------------------------------------------------------

-- Trouve le token de raid/groupe correspondant à un nom de joueur.
local function FindUnitToken(playerName)
    for i = 1, 40 do
        local token = "raid" .. i
        if UnitExists(token) then
            local name = Ambiguate(GetUnitName(token, true), "short")
            if name == playerName then return token end
        end
    end
    for i = 1, 4 do
        local token = "party" .. i
        if UnitExists(token) then
            local name = Ambiguate(GetUnitName(token, true), "short")
            if name == playerName then return token end
        end
    end
    return nil
end

-- Trouve le frame de raid Blizzard associé à un unit token.
local function FindRaidFrame(unitToken)
    for i = 1, 40 do
        local f = _G["CompactRaidFrame" .. i]
        if f and f.unit == unitToken then return f end
    end
    if CompactPartyFrame then
        local function ScanChildren(parent)
            for _, child in ipairs({ parent:GetChildren() }) do
                if child.unit and child.unit == unitToken then return child end
                local found = ScanChildren(child)
                if found then return found end
            end
        end
        local found = ScanChildren(CompactPartyFrame)
        if found then return found end
    end
    if CompactRaidFrameContainer then
        local function ScanChildren(parent)
            for _, child in ipairs({ parent:GetChildren() }) do
                if child.unit and child.unit == unitToken then return child end
                local found = ScanChildren(child)
                if found then return found end
            end
        end
        local found = ScanChildren(CompactRaidFrameContainer)
        if found then return found end
    end
    return nil
end

-- Supprime le highlight d'un joueur.
local function RemoveHighlight(unitToken)
    local h = activeHighlights[unitToken]
    if not h then return end
    if h.ticker then h.ticker:Cancel() end
    if h.overlay and h.overlay:IsShown() then h.overlay:Hide() end
    activeHighlights[unitToken] = nil
end

-- Crée ou rafraîchit le highlight sur le frame du joueur.
function PIReq_Highlight(playerName)
    -- Notification aura : toujours affichée, indépendamment du raid frame.
    ShowNotification(playerName)

    local unitToken = FindUnitToken(playerName)
    if not unitToken then return end

    RemoveHighlight(unitToken)

    local raidFrame = FindRaidFrame(unitToken)
    if not raidFrame then return end

    local overlay = CreateFrame("Frame", nil, raidFrame)
    overlay:SetAllPoints(raidFrame)
    overlay:SetFrameLevel(raidFrame:GetFrameLevel() + 10)

    local BORDER = 4
    local borders = {}

    local top = overlay:CreateTexture(nil, "OVERLAY")
    top:SetColorTexture(1, 0.84, 0, 1)
    top:SetPoint("TOPLEFT",     overlay, "TOPLEFT",      0,  0)
    top:SetPoint("BOTTOMRIGHT", overlay, "TOPRIGHT",     0, -BORDER)
    table.insert(borders, top)

    local bot = overlay:CreateTexture(nil, "OVERLAY")
    bot:SetColorTexture(1, 0.84, 0, 1)
    bot:SetPoint("TOPLEFT",     overlay, "BOTTOMLEFT",   0,  BORDER)
    bot:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT",  0,  0)
    table.insert(borders, bot)

    local lft = overlay:CreateTexture(nil, "OVERLAY")
    lft:SetColorTexture(1, 0.84, 0, 1)
    lft:SetPoint("TOPLEFT",     overlay, "TOPLEFT",      0, -BORDER)
    lft:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMLEFT",   BORDER, BORDER)
    table.insert(borders, lft)

    local rgt = overlay:CreateTexture(nil, "OVERLAY")
    rgt:SetColorTexture(1, 0.84, 0, 1)
    rgt:SetPoint("TOPLEFT",     overlay, "TOPRIGHT",    -BORDER, -BORDER)
    rgt:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT",  0,       BORDER)
    table.insert(borders, rgt)

    overlay:Show()

    local startTime = GetTime()
    local ticker = C_Timer.NewTicker(0.05, function()
        local elapsed = GetTime() - startTime
        if elapsed >= HIGHLIGHT_DURATION then
            RemoveHighlight(unitToken)
            return
        end
        local alpha = PULSE_MIN + (PULSE_MAX - PULSE_MIN) *
                      (0.5 + 0.5 * math.sin(elapsed * PULSE_SPEED * math.pi * 2))
        for _, t in ipairs(borders) do
            t:SetAlpha(alpha)
        end
    end)

    activeHighlights[unitToken] = {
        overlay   = overlay,
        borders   = borders,
        startTime = startTime,
        ticker    = ticker,
    }
end

-- Supprime le highlight après cast de PI (V2).
function PIReq_ClearHighlight(playerName)
    local unitToken = FindUnitToken(playerName)
    if unitToken then RemoveHighlight(unitToken) end
end

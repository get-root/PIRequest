-- PIRequest — Highlighter.lua
-- Côté prêtre : highlight de la barre de vie du DPS demandeur.

local HIGHLIGHT_DURATION = 15   -- secondes avant suppression automatique
local PULSE_MIN          = 0.4
local PULSE_MAX          = 1.0
local PULSE_SPEED        = 2.0  -- cycles par seconde

local activeHighlights = {}  -- [unitToken] = { overlay, startTime, ticker }

-- Trouve le token de raid/groupe correspondant à un nom de joueur.
local function FindUnitToken(playerName)
    -- Raid
    for i = 1, 40 do
        local token = "raid" .. i
        if UnitExists(token) then
            local name = Ambiguate(GetUnitName(token, true), "short")
            if name == playerName then return token end
        end
    end
    -- Groupe (M+)
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
    -- CompactRaidFrames (interface Blizzard par défaut)
    if CompactRaidFrameContainer then
        local function ScanChildren(parent)
            for _, child in ipairs({ parent:GetChildren() }) do
                if child.unit and child.unit == unitToken then
                    return child
                end
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
    local unitToken = FindUnitToken(playerName)
    if not unitToken then
        print("|cffff6600[PIRequest]|r Frame introuvable pour " .. playerName .. ".")
        return
    end

    -- Supprime un éventuel highlight existant sur ce joueur.
    RemoveHighlight(unitToken)

    local raidFrame = FindRaidFrame(unitToken)
    if not raidFrame then
        print("|cffff6600[PIRequest]|r Frame de raid introuvable pour " .. playerName .. ".")
        return
    end

    -- Crée l'overlay de bordure dorée.
    local overlay = CreateFrame("Frame", nil, raidFrame)
    overlay:SetAllPoints(raidFrame)
    overlay:SetFrameLevel(raidFrame:GetFrameLevel() + 10)

    local tex = overlay:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints(overlay)
    tex:SetColorTexture(1, 0.84, 0, 1)  -- #FFD700
    tex:SetAlpha(PULSE_MIN)

    -- Masque pour ne garder que la bordure (4 px).
    local BORDER = 4
    local inner = overlay:CreateTexture(nil, "OVERLAY")
    inner:SetColorTexture(0, 0, 0, 0)
    inner:SetPoint("TOPLEFT",     overlay, "TOPLEFT",   BORDER,  -BORDER)
    inner:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", -BORDER, BORDER)
    -- On efface le centre avec un frame opaque noir transparent via blend.
    -- Approche simple : texture pleine + découpe via SetBlendMode n'est pas
    -- disponible facilement, donc on utilise 4 textures pour les bords.
    tex:Hide()

    -- 4 textures pour les 4 bords.
    local borders = {}
    local function MakeBorder(point, relPoint, x1, y1, x2, y2)
        local t = overlay:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(1, 0.84, 0, 1)
        t:SetPoint(point, overlay, relPoint, x1, y1)
        t:SetPoint(relPoint == "TOPLEFT" and "BOTTOMRIGHT" or
                   relPoint == "TOPRIGHT" and "BOTTOMLEFT" or
                   relPoint == "BOTTOMLEFT" and "TOPRIGHT" or "TOPLEFT",
                   overlay, relPoint, x2, y2)
        table.insert(borders, t)
    end

    -- Haut
    local top = overlay:CreateTexture(nil, "OVERLAY")
    top:SetColorTexture(1, 0.84, 0, 1)
    top:SetPoint("TOPLEFT",     overlay, "TOPLEFT",      0, 0)
    top:SetPoint("BOTTOMRIGHT", overlay, "TOPRIGHT",     0, -BORDER)
    table.insert(borders, top)
    -- Bas
    local bot = overlay:CreateTexture(nil, "OVERLAY")
    bot:SetColorTexture(1, 0.84, 0, 1)
    bot:SetPoint("TOPLEFT",     overlay, "BOTTOMLEFT",   0,  BORDER)
    bot:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT",  0,  0)
    table.insert(borders, bot)
    -- Gauche
    local lft = overlay:CreateTexture(nil, "OVERLAY")
    lft:SetColorTexture(1, 0.84, 0, 1)
    lft:SetPoint("TOPLEFT",     overlay, "TOPLEFT",      0, -BORDER)
    lft:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMLEFT",   BORDER, BORDER)
    table.insert(borders, lft)
    -- Droite
    local rgt = overlay:CreateTexture(nil, "OVERLAY")
    rgt:SetColorTexture(1, 0.84, 0, 1)
    rgt:SetPoint("TOPLEFT",     overlay, "TOPRIGHT",    -BORDER, -BORDER)
    rgt:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT",  0,       BORDER)
    table.insert(borders, rgt)

    overlay:Show()

    local startTime = GetTime()

    -- Ticker pour le pulse alpha et le timeout.
    local ticker = C_Timer.NewTicker(0.05, function()
        local elapsed = GetTime() - startTime

        -- Timeout automatique.
        if elapsed >= HIGHLIGHT_DURATION then
            RemoveHighlight(unitToken)
            return
        end

        -- Pulse alpha sinusoïdal.
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

-- Supprime le highlight après cast de PI (à appeler depuis un suivi de spell cast — V2).
function PIReq_ClearHighlight(playerName)
    local unitToken = FindUnitToken(playerName)
    if unitToken then RemoveHighlight(unitToken) end
end

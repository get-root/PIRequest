-- PIRequest — Engine.lua
-- Chemin "auras SECRÈTES" : combat, boss, M+, PvP (12.1+).
--
-- Dans ces contextes Lua ne peut plus rien lire des auras des coéquipiers.
-- On délègue donc au moteur, qui lui a le droit de comparer :
--   * C_UnitAuras.AddAuraSound  → son quand une aura (spellId choisi) est AJOUTÉE
--                                 sur l'unité du coéquipier surveillé
--   * AuraContainer + includeSpellIDs → icône de l'aura (avec nom du joueur) tant
--                                 que le CD est actif, dans un cadre déplaçable
--
-- Aucun callback Lua n'existe pour ces deux mécanismes : pas de bannière ni de
-- surbrillance de raid frame dans ce mode, uniquement son + icône.
--
-- Méthode inspirée de la façon dont EllesmereUI affiche les auras (AuraContainer
-- filtré par spellId) ; aucun code ni aucune liste n'en est copié.

local SOUND_FILE  = (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959
local MAX_SOUNDS  = 300   -- garde-fou : unités × sorts
local MAX_ROWS    = 10
local ICON        = 40
local GAP         = 22    -- place pour le nom sous l'icône
local NO_UNIT     = "none"
local GROUP_KEY   = "pirequest"

local soundIds      = {}
local pool          = {}  -- [unit.."|"..name] = container
local active        = {}  -- containers actuellement assignés
local tracker, unlocked
local pendingSync   = false
local errShown      = false

local function Err(msg)
    if PIReq.debugMode or not errShown then
        errShown = true
        PIReq.Print("|cffff6600" .. msg .. "|r")
    end
end

function PIReq_EngineStats()
    return #soundIds, #active
end

-- ---------------------------------------------------------------------------
-- Sons moteur
-- ---------------------------------------------------------------------------

local function ClearSounds()
    if C_UnitAuras and C_UnitAuras.RemoveAuraSound then
        for _, id in ipairs(soundIds) do pcall(C_UnitAuras.RemoveAuraSound, id) end
    end
    wipe(soundIds)
    PIReq.engineSoundActive = false
end

-- Retourne false si au moins un enregistrement a été refusé (à retenter plus tard).
local function RegisterSounds(units)
    ClearSounds()
    if not PIReq.DB.sound then return true end
    if not (C_UnitAuras and C_UnitAuras.AddAuraSound) then return true end

    local trigger = (Enum and Enum.UnitAuraSoundTrigger and Enum.UnitAuraSoundTrigger.Added) or 0
    local failed = false
    for _, unit in ipairs(units) do
        for spellId in pairs(PIReq.spellSet) do
            if #soundIds >= MAX_SOUNDS then
                Err("trop de sons moteur (" .. MAX_SOUNDS .. "), liste tronquée : utilise le filtre par nom.")
                PIReq.engineSoundActive = #soundIds > 0
                return true
            end
            local ok, id = pcall(C_UnitAuras.AddAuraSound, trigger, {
                unitToken       = unit,
                spellID         = spellId,
                soundFileID     = SOUND_FILE,
                outputChannel   = "Master",
                throttleSeconds = 5,
            })
            if ok and id then
                soundIds[#soundIds + 1] = id
            else
                failed = true
                if PIReq.debugMode then
                    PIReq.Print("AddAuraSound refusé : " .. unit .. " / " .. spellId .. " → " .. tostring(id))
                end
            end
        end
    end
    PIReq.engineSoundActive = #soundIds > 0
    return not failed
end

-- ---------------------------------------------------------------------------
-- Cadre du tracker (déplaçable)
-- ---------------------------------------------------------------------------

local function SavePosition(f)
    local point, _, relPoint, x, y = f:GetPoint()
    PIReq.DB.trackerPos = { point, relPoint, x, y }
end

local function EnsureTracker()
    if tracker then return tracker end
    local f = CreateFrame("Frame", "PIReqTracker", UIParent)
    f:SetSize(ICON * 3 + 16, ICON + GAP)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)

    local pos = PIReq.DB.trackerPos
    if pos then
        f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        f:SetPoint("CENTER", UIParent, "CENTER", -300, 120)
    end

    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if unlocked then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePosition(self) end)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetColorTexture(1, 0.84, 0, 0.25)
    bg:Hide()
    f.bg = bg

    local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER")
    label:SetText("PIRequest — glisser pour déplacer")
    label:Hide()
    f.label = label

    f:EnableMouse(false)
    tracker = f
    return f
end

function PIReq_ToggleTrackerUnlock()
    local f = EnsureTracker()
    unlocked = not unlocked
    f:EnableMouse(unlocked)
    f.bg:SetShown(unlocked)
    f.label:SetShown(unlocked)
    PIReq.Print(unlocked and "Tracker déverrouillé : glisse-le, puis /pirequest tracker pour verrouiller."
                          or  "Tracker verrouillé.")
end

-- ---------------------------------------------------------------------------
-- Containers d'auras (un par joueur surveillé)
-- ---------------------------------------------------------------------------

local function IncludeSet()
    local set = {}
    for id in pairs(PIReq.spellSet) do set[id] = true end
    return set
end

local function MakeInitializer(name)
    return function(button)
        pcall(button.SetMouseClickEnabled, button, false)

        local border = button:CreateTexture(nil, "BACKGROUND")
        border:SetPoint("TOPLEFT", -2, 2)
        border:SetPoint("BOTTOMRIGHT", 2, -2)
        border:SetColorTexture(1, 0.84, 0, 1)

        local icon = button:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(button)

        local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        cd:SetAllPoints(button)

        -- Le nom vit sur le bouton : il n'apparaît donc que quand une aura est affichée.
        local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("TOP", button, "BOTTOM", 0, -3)
        text:SetText(name)

        -- Enregistrer les régions APRÈS leur création/stylage (cf. moteur).
        button:SetIcon(icon)
        button:SetDurationCooldown(cd)
    end
end

local function CreateRowContainer(unit, name)
    if C_AddOns and C_AddOns.IsAddOnLoaded and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
        C_AddOns.LoadAddOn("Blizzard_AuraContainer")
    end
    local c = CreateFrame("AuraContainer", nil, EnsureTracker(), "CustomAuraContainerTemplate")
    c:SetSize(1, 1) -- le moteur remplace la taille ; il lui faut un rect dès le départ
    c:AddAuraGroup(GROUP_KEY, "HELPFUL", {
        maxFrameCount    = 3,
        candidateFilters = { includeSpellIDs = IncludeSet() },
        initializeFrame  = MakeInitializer(name),
        layout           = { elementWidth = ICON, elementHeight = ICON, elementSpacing = 6, lineSpacing = 6 },
    })
    return c
end

local function ParkAll()
    for _, c in ipairs(active) do pcall(c.SetUnit, c, NO_UNIT) end
    wipe(active)
end

local function SyncContainers(units)
    ParkAll()
    if not PIReq.DB.tracker or #units == 0 or next(PIReq.spellSet) == nil then
        return
    end
    local f = EnsureTracker()
    for i, unit in ipairs(units) do
        if i > MAX_ROWS then break end
        local name = PIReq.UnitShortName(unit) or unit
        local key  = unit .. "|" .. name
        local c = pool[key]
        if not c then
            local ok, res = pcall(CreateRowContainer, unit, name)
            if ok then
                c = res
                pool[key] = c
            else
                Err("création du container impossible : " .. tostring(res))
            end
        end
        if c then
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(i - 1) * (ICON + GAP))
            -- Filtre à jour (la sélection de sorts a pu changer).
            if c.SetAuraGroupCandidateFilters then
                pcall(c.SetAuraGroupCandidateFilters, c, GROUP_KEY, { includeSpellIDs = IncludeSet() })
            end
            local ok, err = pcall(c.SetUnit, c, unit)
            if ok then
                active[#active + 1] = c
            else
                Err("SetUnit(" .. unit .. ") refusé : " .. tostring(err))
            end
        end
    end
    f:SetHeight(math.max(1, math.min(#units, MAX_ROWS)) * (ICON + GAP))
end

-- ---------------------------------------------------------------------------
-- API publique
-- ---------------------------------------------------------------------------

function PIReq_EngineSync()
    if InCombatLockdown() then
        pendingSync = true -- retenté à PLAYER_REGEN_ENABLED
        return
    end
    pendingSync = false
    local units = PIReq.TrackedUnits()
    local soundsOk = RegisterSounds(units)
    SyncContainers(units)
    if not soundsOk then pendingSync = true end
end

function PIReq_EngineStop()
    pendingSync = false
    ClearSounds()
    ParkAll()
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:SetScript("OnEvent", function()
    if pendingSync and PIReq.DB and PIReq.isPriest and PIReq.DB.enabled then
        PIReq_EngineSync()
    end
end)

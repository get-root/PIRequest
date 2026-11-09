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

local MAX_SOUNDS  = 300   -- garde-fou : unités × sorts
local MAX_ROWS    = 10
local ICON        = 52
local GAP         = 30    -- place pour le nom sous l'icône
local NO_UNIT     = "none"
local GROUP_KEY   = "pirequest"

local soundIds      = {}
local pool          = {}  -- [unit.."|"..name] = container
local active        = {}  -- containers actuellement assignés
local tracker, unlocked
local pendingSync   = false
local retries       = 0
local errShown      = false

-- Journal du moteur (affiché par /pirequest scan et /pirequest resync).
local logLines, verbose = {}, false
local function Log(msg)
    logLines[#logLines + 1] = date("%H:%M:%S ") .. msg
    if #logLines > 30 then table.remove(logLines, 1) end
    if verbose or PIReq.debugMode then PIReq.Print("[moteur] " .. msg) end
end

local function Err(msg)
    Log("ERREUR " .. msg)
    if not errShown then
        errShown = true
        PIReq.Print("|cffff6600" .. msg .. "|r")
    end
end

function PIReq_EngineVerbose(v) verbose = v end

-- Diagnostic /pirequest scan : état réel des containers.
function PIReq_EngineDebug()
    local lines = {}
    if not tracker then
        lines[#lines + 1] = "tracker non créé (aucune unité/aucun sort, ou option désactivée)"
        lines[#lines + 1] = string.format("contexte : PI en recharge=%s pendingSync=%s combat=%s option tracker=%s",
            tostring(PIReq.AlertsMuted()), tostring(pendingSync), tostring(InCombatLockdown()), tostring(PIReq.DB.tracker))
        for i = math.max(1, #logLines - 9), #logLines do lines[#lines + 1] = logLines[i] end
        return lines
    end
    local ok, shown = pcall(tracker.IsShown, tracker)
    lines[#lines + 1] = string.format("tracker : shown=%s alpha=%s", tostring(ok and shown), tostring(tracker:GetEffectiveAlpha()))
    for i, c in ipairs(active) do
        local o1, u = pcall(c.GetUnit, c)
        local o2, sh = pcall(c.IsShown, c)
        local o3, w = pcall(c.GetWidth, c)
        local o4, h = pcall(c.GetHeight, c)
        lines[#lines + 1] = string.format("container %d : unit=%s shown=%s taille=%sx%s", i,
            tostring(o1 and u), tostring(o2 and sh), tostring(o3 and w), tostring(o4 and h))
    end
    if #active == 0 then lines[#lines + 1] = "aucun container actif" end
    lines[#lines + 1] = string.format("contexte : PI en recharge=%s pendingSync=%s combat=%s option tracker=%s",
        tostring(PIReq.AlertsMuted()), tostring(pendingSync), tostring(InCombatLockdown()), tostring(PIReq.DB.tracker))
    lines[#lines + 1] = "-- journal moteur (derniers) --"
    for i = math.max(1, #logLines - 9), #logLines do lines[#lines + 1] = logLines[i] end
    return lines
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
    if not (C_UnitAuras and C_UnitAuras.AddAuraSound) then
        Err("C_UnitAuras.AddAuraSound indisponible : pas de son en combat/donjon.")
        return true
    end

    local trigger = (Enum and Enum.UnitAuraSoundTrigger and Enum.UnitAuraSoundTrigger.Added) or 0
    local failed = false
    local _, soundFile = PIReq.GetSound()
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
                soundFileID     = soundFile, -- FileDataID (≠ SoundKit)
                outputChannel   = "Master",
                throttleSeconds = 5,
            })
            if ok and id then
                soundIds[#soundIds + 1] = id
            else
                failed = true
                -- Visible une fois par session (sinon l'échec est silencieux et
                -- l'utilisateur n'entend simplement jamais rien).
                Err("AddAuraSound refusé (" .. unit .. " / " .. spellId .. ") : " .. tostring(id)
                    .. " — nouvel essai automatique.")
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
        f:SetPoint("TOP", UIParent, "TOP", 0, -330) -- sous la bannière
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

    -- Exemple (icône PI + nom) pour voir le placement sans attendre un vrai CD.
    local sample = CreateFrame("Frame", nil, f)
    sample:SetAllPoints(f)
    local sb = sample:CreateTexture(nil, "BACKGROUND")
    sb:SetSize(ICON + 4, ICON + 4)
    sb:SetPoint("TOPLEFT", -2, 2)
    sb:SetColorTexture(1, 0.84, 0, 1)
    local si = sample:CreateTexture(nil, "ARTWORK")
    si:SetSize(ICON, ICON)
    si:SetPoint("TOPLEFT")
    local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(10060)
    if tex then si:SetTexture(tex) end
    local st = sample:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    st:SetPoint("TOP", si, "BOTTOM", 0, -3)
    st:SetText(UnitName("player") or "Joueur")
    sample:Hide()
    f.sample = sample

    f:EnableMouse(false)
    tracker = f
    return f
end

local previewTimer
local function UpdateSample()
    if not tracker then return end
    tracker.sample:SetShown(unlocked or previewTimer ~= nil)
end

-- Affiche l'exemple quelques secondes (/pirequest test).
function PIReq_TrackerPreview(seconds)
    EnsureTracker()
    if previewTimer then previewTimer:Cancel() end
    previewTimer = C_Timer.NewTimer(seconds or 5, function() previewTimer = nil; UpdateSample() end)
    UpdateSample()
end

function PIReq_ToggleTrackerUnlock()
    local f = EnsureTracker()
    unlocked = not unlocked
    f:EnableMouse(unlocked)
    f.bg:SetShown(unlocked)
    f.label:SetShown(unlocked)
    UpdateSample()
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
        local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
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
    for _, c in ipairs(active) do
        pcall(c.SetUnit, c, NO_UNIT)
        if c.SetEnabled then pcall(c.SetEnabled, c, false) end
    end
    wipe(active)
end

local function SyncContainers(units)
    ParkAll()
    Log(string.format("containers : unités=%d tracker=%s sorts=%s",
        #units, tostring(PIReq.DB.tracker), tostring(next(PIReq.spellSet) ~= nil)))
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
                Log("container créé pour " .. unit .. " (" .. name .. ")")
            else
                Err("création du container impossible (" .. unit .. ") : " .. tostring(res))
            end
        end
        if c then
            pcall(c.ClearAllPoints, c)
            pcall(c.SetPoint, c, "TOPLEFT", f, "TOPLEFT", 0, -(i - 1) * (ICON + GAP))
            pcall(c.Show, c)
            -- Filtre à jour (la sélection de sorts a pu changer).
            if c.SetAuraGroupCandidateFilters then
                local okF, eF = pcall(c.SetAuraGroupCandidateFilters, c, GROUP_KEY, { includeSpellIDs = IncludeSet() })
                if not okF then Err("SetAuraGroupCandidateFilters : " .. tostring(eF)) end
            end
            -- Un AuraContainer n'écoute UNIT_AURA que s'il est VISIBLE ET ACTIVÉ
            -- (IsVisible() and IsEnabled()) ; SetEnabled/SetUnit relancent eux-mêmes
            -- le rafraîchissement. UpdateAllAuras n'est qu'un filet : son échec
            -- ne doit pas écarter le container.
            if c.SetEnabled then
                local okE, eE = pcall(c.SetEnabled, c, true)
                if not okE then Err("SetEnabled : " .. tostring(eE)) end
            end
            local okS, eS = pcall(c.SetUnit, c, unit)
            if not okS then Err("SetUnit(" .. unit .. ") : " .. tostring(eS)) end
            if okS and c.UpdateAllAuras then
                local okU, eU = pcall(c.UpdateAllAuras, c)
                if not okU then Log("UpdateAllAuras (non bloquant) : " .. tostring(eU)) end
            end
            if okS then active[#active + 1] = c end

            local o1, en  = pcall(c.IsEnabled, c)
            local o2, vis = pcall(c.IsVisible, c)
            local o3, u   = pcall(c.GetUnit, c)
            Log(string.format("%s : enabled=%s visible=%s unit=%s", unit,
                tostring(o1 and en), tostring(o2 and vis), tostring(o3 and u)))
        end
    end
    f:SetHeight(math.max(1, math.min(#units, MAX_ROWS)) * (ICON + GAP))
end

-- ---------------------------------------------------------------------------
-- API publique
-- ---------------------------------------------------------------------------

function PIReq_EngineSync()
    if PIReq.AlertsMuted() then
        Log("sync ignoré : PI en recharge (alertes coupées)")
        -- PI en recharge : on retire sons et icônes même en combat (pas de création).
        ClearSounds()
        ParkAll()
        pendingSync = false
        return
    end
    -- Pas de report en combat : la création de containers y est légale (12.1) et
    -- sinon, quand PI redevient disponible en plein combat, on resterait sans son
    -- ni icône jusqu'à la fin du combat. Un refus d'AddAuraSound est retenté.
    pendingSync = false
    local units = PIReq.ActiveUnits()
    Log(string.format("sync : unités=%d combat=%s secret=%s", #units,
        tostring(InCombatLockdown()), tostring(PIReq.IsRestricted())))
    local soundsOk = RegisterSounds(units)
    local okC, eC = pcall(SyncContainers, units)
    if not okC then Err("SyncContainers : " .. tostring(eC)) end
    if not soundsOk then
        pendingSync = true
        -- Nouvel essai temporisé (3 max) sans attendre la fin d'un combat.
        retries = retries + 1
        if retries <= 10 then
            C_Timer.After(5, function()
                if pendingSync and PIReq.isPriest and PIReq.DB.enabled then PIReq_EngineSync() end
            end)
        end
    else
        retries = 0
    end
end

-- Diagnostic /pirequest ctest [unit] [filtre] : affiche pendant 20 s un container
-- SANS filtre de sort (ou avec, si "filtre") sur l'unité donnée (défaut : player).
--  * affiche tes buffs  → le rendu du container fonctionne, le souci est le filtre/les sorts
--  * n'affiche rien      → le rendu lui-même (initializeFrame / placement) est en cause
local testContainer
function PIReq_EngineContainerTest(unit, useFilter)
    unit = (unit and unit ~= "") and unit or "player"
    local f = EnsureTracker()
    if not testContainer then
        local ok, res = pcall(function()
            if C_AddOns and C_AddOns.IsAddOnLoaded and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then
                C_AddOns.LoadAddOn("Blizzard_AuraContainer")
            end
            local c = CreateFrame("AuraContainer", nil, f, "CustomAuraContainerTemplate")
            c:SetSize(1, 1)
            c:AddAuraGroup("test", "HELPFUL", {
                maxFrameCount   = 8,
                initializeFrame = MakeInitializer("test"),
                layout          = { elementWidth = ICON, elementHeight = ICON, elementSpacing = 6, lineSpacing = 6 },
            })
            return c
        end)
        if not ok then Err("ctest : création impossible : " .. tostring(res)) return end
        testContainer = res
    end
    local c = testContainer
    local okF, eF = pcall(c.SetAuraGroupCandidateFilters, c, "test", useFilter and { includeSpellIDs = IncludeSet() } or {})
    if not okF then Err("ctest : filtres : " .. tostring(eF)) end
    pcall(c.ClearAllPoints, c)
    pcall(c.SetPoint, c, "TOPLEFT", f, "BOTTOMLEFT", 0, -20)
    pcall(c.Show, c)
    pcall(c.SetEnabled, c, true)
    local okS, eS = pcall(c.SetUnit, c, unit)
    if not okS then Err("ctest : SetUnit : " .. tostring(eS)) return end
    local _, w = pcall(c.GetWidth, c)
    local _, h = pcall(c.GetHeight, c)
    PIReq.Print(string.format("ctest : container sur %s (%s), taille %sx%s, 20 s. Buffs visibles sous le tracker ?",
        unit, useFilter and "filtre CDs" or "tous les buffs", tostring(w), tostring(h)))
    C_Timer.After(20, function()
        pcall(c.SetUnit, c, NO_UNIT)
        pcall(c.SetEnabled, c, false)
    end)
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

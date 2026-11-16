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

local soundSig            -- signature du dernier enregistrement de sons réussi
local soundIds      = {}
local pool          = {}  -- [unit.."|"..name] = container
local active        = {}  -- containers actuellement assignés
local tracker, unlocked
local pendingSync   = false
local retryTimer    = false
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
    lines[#lines + 1] = string.format("icônes : initialiseur appelé %d fois, %d étape(s) en échec%s",
        initCalls, initFails, initLastErr and (" — " .. initLastErr) or "")
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
    soundSig = nil
    PIReq.engineSoundActive = false
end

-- Retourne false si au moins un enregistrement a été refusé (à retenter plus tard).
local issecret = issecretvalue or function() return false end

-- Classe d'une unité (nil si illisible → on enregistre alors tous les sorts).
local function UnitClassFile(unit)
    local ok, _, class = pcall(UnitClass, unit)
    if ok and type(class) == "string" and not issecret(class) then return class end
    return nil
end

local function RegisterSounds(units)
    -- Rien n'a changé (mêmes unités/classes, mêmes sorts, même son) : on garde
    -- les sons en place.
    local _, soundFile = PIReq.GetSound()
    local parts = { tostring(PIReq.DB.sound), tostring(soundFile), tostring(PIReq.spellSetVersion) }
    for _, unit in ipairs(units) do parts[#parts + 1] = unit .. ":" .. tostring(UnitClassFile(unit)) end
    local sig = table.concat(parts, "|")
    if sig == soundSig then return true end

    if not PIReq.DB.sound or #units == 0 then
        ClearSounds()
        soundSig = sig
        return true
    end
    if not (C_UnitAuras and C_UnitAuras.AddAuraSound) then
        Err("C_UnitAuras.AddAuraSound indisponible : pas de son en combat/donjon.")
        return true
    end

    -- Liste voulue : par joueur, seulement les CDs de SA classe (+ potions et
    -- IDs perso), ~10 sons au lieu de ~45.
    local wanted = {}
    for _, unit in ipairs(units) do
        local unitClass = UnitClassFile(unit)
        for spellId in pairs(PIReq.spellSet) do
            local cls = PIReq.spellClass and PIReq.spellClass[spellId]
            if not (cls and cls ~= "POTION" and unitClass and cls ~= unitClass) then
                wanted[#wanted + 1] = { unit, spellId }
            end
        end
    end
    if #wanted > MAX_SOUNDS then
        Err("trop de sons moteur (" .. MAX_SOUNDS .. "), liste tronquée : utilise le filtre par nom.")
        for i = #wanted, MAX_SOUNDS + 1, -1 do wanted[i] = nil end
    end

    -- ⚠️ AddAuraSound est une API « restreinte » : en contexte secret (clé M+,
    -- combat) le moteur peut REFUSER un nouvel enregistrement. On ajoute donc
    -- d'abord les nouveaux sons et on ne retire les anciens qu'une fois le
    -- premier ajout accepté : un refus laisse les sons existants intacts au
    -- lieu de rendre l'addon muet jusqu'à la fin de la clé.
    local trigger = (Enum and Enum.UnitAuraSoundTrigger and Enum.UnitAuraSoundTrigger.Added) or 0
    local old, newIds, failed = soundIds, {}, 0
    for i, w in ipairs(wanted) do
        local info = { unitToken = w[1], spellID = w[2], outputChannel = "Master", throttleSeconds = 5 }
        -- FileDataID (≠ SoundKit) ou chemin de fichier (son d'un addon).
        if type(soundFile) == "string" then info.soundFileName = soundFile
        else info.soundFileID = soundFile end
        local ok, id = pcall(C_UnitAuras.AddAuraSound, trigger, info)
        if ok and id then
            newIds[#newIds + 1] = id
        else
            failed = failed + 1
            if i == 1 then
                Log(string.format("AddAuraSound refusé (%s / %s) : %s — %d ancien(s) son(s) conservé(s), secret=%s combat=%s",
                    w[1], tostring(w[2]), tostring(id), #old, tostring(PIReq.IsRestricted()), tostring(InCombatLockdown())))
                return false
            end
        end
    end
    if C_UnitAuras.RemoveAuraSound then
        for _, id in ipairs(old) do pcall(C_UnitAuras.RemoveAuraSound, id) end
    end
    soundIds = newIds
    PIReq.engineSoundActive = #soundIds > 0
    Log(string.format("sons : %d enregistrés, %d refusés, %d anciens retirés", #newIds, failed, #old))
    if failed == 0 then soundSig = sig return true end
    soundSig = nil
    return false
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

-- Compteurs de diagnostic (affichés par /pirequest ctest et /pirequest scan).
local initCalls, initFails, initLastErr = 0, 0, nil

local function MakeInitializer(name)
    -- Le moteur appelle l'initialiseur via securecallfunction : une erreur y
    -- serait avalée sans bruit. Chaque étape est donc protégée séparément (un
    -- échec sur le cooldown ne doit pas empêcher l'icône) et journalisée.
    return function(button)
        initCalls = initCalls + 1
        local function step(label, fn)
            local ok, err = pcall(fn)
            if not ok then
                initFails = initFails + 1
                initLastErr = label .. " : " .. tostring(err)
                Err("icône, étape « " .. label .. " » : " .. tostring(err))
            end
            return ok
        end

        -- CustomAuraButtonTemplate n'a AUCUNE taille et le flow layout du moteur
        -- ne fait que positionner : sans ceci le bouton fait 0×0.
        step("taille", function() button:SetSize(ICON, ICON) end)

        local icon
        step("icône", function()
            icon = button:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints(button)
            button:SetIcon(icon)
        end)
        step("bordure", function()
            local border = button:CreateTexture(nil, "BACKGROUND")
            border:SetPoint("TOPLEFT", -2, 2)
            border:SetPoint("BOTTOMRIGHT", 2, -2)
            border:SetColorTexture(1, 0.84, 0, 1)
        end)
        -- Le nom vit sur le bouton : il n'apparaît que quand une aura est affichée.
        step("nom", function()
            local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            text:SetPoint("TOP", button, "BOTTOM", 0, -3)
            text:SetText(name)
        end)
        step("cooldown", function()
            local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
            cd:SetAllPoints(button)
            button:SetDurationCooldown(cd)
        end)
        step("souris", function() button:SetMouseClickEnabled(false) end)
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
    -- ⚠️ On ne retire PLUS rien pendant la recharge de PI. Retirer les sons puis
    -- les remettre 2 min plus tard se fait forcément en contexte secret (clé,
    -- combat), où le moteur refuse les nouveaux enregistrements : le son
    -- marchait une fois puis plus jamais. Sons et icônes sont posés une fois
    -- et restent ; `hideOnCooldown` ne concerne que la bannière (AuraWatcher).
    pendingSync = false
    local units = PIReq.TrackedUnits()
    Log(string.format("sync : unités=%d combat=%s secret=%s", #units,
        tostring(InCombatLockdown()), tostring(PIReq.IsRestricted())))
    local soundsOk = RegisterSounds(units)
    local okC, eC = pcall(SyncContainers, units)
    if not okC then Err("SyncContainers : " .. tostring(eC)) end
    if not soundsOk then
        -- Refus (contexte secret) : nouvel essai toutes les 15 s tant que ça
        -- échoue, plus à chaque fin de combat / changement de zone ou de groupe.
        pendingSync = true
        if not retryTimer then
            retryTimer = true
            C_Timer.After(15, function()
                retryTimer = false
                if pendingSync and PIReq.DB and PIReq.isPriest and PIReq.DB.enabled then PIReq_EngineSync() end
            end)
        end
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
    -- Rapport automatique : dit où ça casse sans avoir à interpréter l'écran.
    C_Timer.After(1.5, function()
        local function try(fn, ...) local ok, v, v2 = pcall(fn, ...) if ok then return v, v2 end return "ERR:" .. tostring(v) end
        PIReq.Print(string.format("ctest rapport : initialiseur appelé %d fois, %d étape(s) en échec%s",
            initCalls, initFails, initLastErr and (" — dernière : " .. initLastErr) or ""))
        PIReq.Print(string.format("ctest container : visible=%s activé=%s unité=%s taille=%sx%s secret=%s",
            tostring(try(c.IsVisible, c)), tostring(try(c.IsEnabled, c)), tostring(try(c.GetUnit, c)),
            tostring(try(c.GetWidth, c)), tostring(try(c.GetHeight, c)), tostring(PIReq.IsRestricted())))
        local n = try(c.GetAuraGroupFrameCount, c, "test")
        local shownCount, detail = 0, {}
        if type(n) == "number" then
            for i = 1, n do
                local b = try(c.GetAuraGroupFrame, c, "test", i)
                if type(b) == "table" then
                    local sh = try(b.IsShown, b)
                    if sh == true then shownCount = shownCount + 1 end
                    if i <= 2 then
                        local w, h = try(b.GetSize, b)
                        detail[#detail + 1] = string.format("#%d shown=%s taille=%sx%s", i, tostring(sh), tostring(w), tostring(h))
                    end
                end
            end
        end
        PIReq.Print(string.format("ctest boutons : %s créés, %d affichés. %s", tostring(n), shownCount, table.concat(detail, " ; ")))
    end)
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

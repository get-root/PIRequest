-- PIRequest — AuraWatcher.lua
-- Chemin "auras LISIBLES" : monde ouvert hors combat, avant le pull, etc.
--
-- Quand C_Secrets.ShouldAurasBeSecret() est faux, UNIT_AURA fournit des
-- addedAuras dont le spellId est lisible : on le compare simplement à la liste
-- de sorts choisie par l'utilisateur. Dès que les auras deviennent secrètes
-- (combat, boss, M+, PvP) ce chemin se coupe et Engine.lua prend le relais :
-- ici on ne lit JAMAIS rien en contexte restreint.
--
-- (12.1 : l'ancienne méthode v2 — ensembles d'auraInstanceID via
-- GetUnitAuras(IMPORTANT/BIG_DEFENSIVE…) — n'est plus utilisable : ces appels
-- renvoient des secrets ou une erreur quand les auras sont secrètes.)

local DEDUP_WINDOW = 10 -- secondes entre deux alertes pour le même joueur

local issecret = issecretvalue or function() return false end

local watchFrames    = {} -- [unitToken] = frame
local alertCooldowns = {} -- [unitToken] = timestamp dernière alerte
local lastSecretLog  = {} -- anti-spam du log debug

local function TryAlert(unit, spellId)
    local now = GetTime()
    local last = alertCooldowns[unit]
    if last and (now - last) < DEDUP_WINDOW then
        if PIReq.debugMode then
            PIReq.Print(string.format("dédup (%.1fs) sur %s", now - last, unit))
        end
        return
    end
    alertCooldowns[unit] = now

    local name = PIReq.UnitShortName(unit) or unit
    if PIReq.debugMode then
        PIReq.Print("ALERTE (lisible) → " .. unit .. " (" .. name .. ") spell=" .. tostring(spellId))
    end
    -- Le son est joué par le moteur (AddAuraSound) s'il est actif, pour ne pas
    -- le doubler ; sinon on le joue nous-mêmes.
    PIReq_Highlight(name, spellId, PIReq.DB.sound and not PIReq.engineSoundActive)
end

local function OnUnitAura(unit, updateInfo)
    if PIReq.IsRestricted() then                       -- le moteur s'en charge
        if PIReq.debugMode then
            local now = GetTime()
            if (now - (lastSecretLog[unit] or 0)) > 5 then
                lastSecretLog[unit] = now
                PIReq.Print(unit .. " : auras secrètes → bannière impossible, son + icône gérés par le moteur")
            end
        end
        return
    end
    if updateInfo == nil or issecret(updateInfo) then return end
    local added = updateInfo.addedAuras
    if added == nil or issecret(added) then return end

    for _, aura in ipairs(added) do
        local spellId = aura.spellId
        if spellId ~= nil and not issecret(spellId) and PIReq.spellSet[spellId] then
            TryAlert(unit, spellId)
            return
        end
    end
end

function PIReq_StopWatching()
    for token, f in pairs(watchFrames) do
        f:UnregisterAllEvents()
        f:SetScript("OnEvent", nil)
        watchFrames[token] = nil
    end
    alertCooldowns = {}
end

-- Reconstruit la liste (appelé à chaque roster / changement de config).
function PIReq_StartWatching()
    PIReq_StopWatching()

    local units = PIReq.TrackedUnits()
    for _, token in ipairs(units) do
        local f = CreateFrame("Frame")
        f:RegisterUnitEvent("UNIT_AURA", token)
        f:SetScript("OnEvent", function(_, _, unit, updateInfo)
            local ok, err = pcall(OnUnitAura, unit, updateInfo)
            if not ok and PIReq.debugMode then
                PIReq.Print("erreur UNIT_AURA : " .. tostring(err))
            end
        end)
        watchFrames[token] = f
    end

    if PIReq.debugMode then
        PIReq.Print("Watching " .. #units .. " unit(s) (mode lisible)")
    end
end

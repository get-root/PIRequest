-- PIRequest — AuraWatcher.lua
-- Côté prêtre : détecte les CDs offensifs (auras IMPORTANT non défensives)
-- et les potions de burst des coéquipiers via UNIT_AURA.
--
-- Principe (Midnight 12.0.5) : en combat / M+ / boss / PvP, le CONTENU des
-- auras des autres joueurs est secret (spellId, nom…), mais les requêtes
-- filtrées côté serveur via C_UnitAuras.GetUnitAuras(unit, filtre)
-- fonctionnent toujours : la liste retournée et les auraInstanceID restent
-- exploitables. On ne lit jamais le contenu, on compare des ensembles d'IDs.
--
-- CD offensif = aura qui matche HELPFUL|IMPORTANT mais PAS
-- HELPFUL|BIG_DEFENSIVE ni HELPFUL|EXTERNAL_DEFENSIVE.
-- (Même technique que MiniCC, en sens inverse : MiniCC déduplique les
-- défensifs hors des importants, nous les excluons pour ne garder que
-- l'offensif.)

local DEDUP_WINDOW  = 10 -- secondes entre deux alertes pour le même joueur
local REBASE_WINDOW = 3  -- secondes sans alerte après re-randomisation des auraInstanceID

-- issecretvalue n'existe que sur les clients Midnight.
local issecret = issecretvalue or function() return false end

-- Buffs des potions de burst Midnight (le sort d'utilisation applique l'aura).
-- IDs résolus via wago.tools (ItemXItemEffect → ItemEffect.SpellID).
-- Le spellId d'une aura adverse n'est lisible que hors conditions secrètes
-- (ex : pre-pot avant le pull) ; en combat, la détection repose sur le filtre
-- IMPORTANT si Blizzard y classe la potion.
local BURST_POTIONS = {
    [1236616] = "Light's Potential",          -- item 241308
    [1236994] = "Potion of Recklessness",     -- item 241288
    [1236998] = "Draught of Rampant Abandon", -- item 241292
    [1238443] = "Potion of Zealotry",         -- item 241296
}

local DEFENSIVE_FILTERS = { "HELPFUL|BIG_DEFENSIVE", "HELPFUL|EXTERNAL_DEFENSIVE" }

local watchFrames    = {} -- [unitToken] = frame
local alertCooldowns = {} -- [unitToken] = timestamp dernière alerte
local offensiveAuras = {} -- [unitToken] = { [auraInstanceID] = true }
local suppressUntil  = 0  -- pas d'alerte avant ce timestamp

-- pcall : tolère un client qui rejette un token de filtre inconnu.
local function GetAuras(unit, filter)
    if not (C_UnitAuras and C_UnitAuras.GetUnitAuras) then return {} end
    local ok, auras = pcall(C_UnitAuras.GetUnitAuras, unit, filter)
    if ok and type(auras) == "table" then return auras end
    return {}
end

-- PI cible un DPS : pas d'alerte pour tank/healer (CDs de heal, trinkets…).
-- Rôle inconnu ("NONE") = on alerte quand même.
local function IsAlertableUnit(unit)
    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
    return role ~= "HEALER" and role ~= "TANK"
end

-- Ensemble des auraInstanceID offensifs importants du unit :
-- IMPORTANT moins (BIG_DEFENSIVE ∪ EXTERNAL_DEFENSIVE).
local function BuildOffensiveSet(unit)
    local set = {}
    if not UnitExists(unit) or UnitIsDeadOrGhost(unit) then return set end

    local defensive = {}
    for _, filter in ipairs(DEFENSIVE_FILTERS) do
        for _, aura in ipairs(GetAuras(unit, filter)) do
            if aura.auraInstanceID then defensive[aura.auraInstanceID] = true end
        end
    end

    for _, aura in ipairs(GetAuras(unit, "HELPFUL|IMPORTANT")) do
        local id = aura.auraInstanceID
        if id and not defensive[id] then
            -- Garde anti-données corrompues (unités hors de portée, cf. MiniCC).
            -- On n'écarte l'aura que sur un false certain ; une secret value
            -- signifie qu'on fait confiance au filtre serveur.
            local keep = true
            local spellId = aura.spellId
            if spellId ~= nil and not issecret(spellId) then
                if C_Spell and C_Spell.IsSpellImportant
                   and C_Spell.IsSpellImportant(spellId) == false then
                    keep = false
                end
                if keep and C_UnitAuras.AuraIsBigDefensive
                   and C_UnitAuras.AuraIsBigDefensive(spellId) == true then
                    keep = false
                end
            end
            if keep then set[id] = true end
        end
    end
    return set
end

local function TryAlert(unit, reason)
    if GetTime() < suppressUntil then
        if PIReq.debugMode then print("[PIReq] alerte supprimée (rebase) sur " .. unit) end
        return
    end
    if not IsAlertableUnit(unit) then
        if PIReq.debugMode then print("[PIReq] " .. unit .. " ignoré (tank/healer)") end
        return
    end
    local now = GetTime()
    local last = alertCooldowns[unit]
    if last and (now - last) < DEDUP_WINDOW then
        if PIReq.debugMode then
            print("[PIReq] dédup (" .. string.format("%.1f", now - last) .. "s) sur " .. unit)
        end
        return
    end
    alertCooldowns[unit] = now
    local name = Ambiguate(GetUnitName(unit, true) or "", "short")
    if PIReq.debugMode then
        print("[PIReq] ALERTE → " .. unit .. " (" .. name .. ") : " .. (reason or "?"))
    end
    PIReq_Highlight(name)
end

-- Potion de burst : ne fonctionne que si le spellId de l'aura ajoutée est
-- lisible (hors combat/M+/boss). Couvre le cas du pre-pot avant le pull.
local function HasBurstPotion(updateInfo)
    if not updateInfo or not updateInfo.addedAuras then return false end
    for _, aura in ipairs(updateInfo.addedAuras) do
        local spellId = aura.spellId
        if spellId ~= nil and not issecret(spellId) and BURST_POTIONS[spellId] then
            return true
        end
    end
    return false
end

local function OnUnitAura(unit, updateInfo)
    local old = offensiveAuras[unit]
    local new = BuildOffensiveSet(unit)
    offensiveAuras[unit] = new

    local hasNew = false
    for id in pairs(new) do
        if not old or not old[id] then
            hasNew = true
            break
        end
    end

    if hasNew then
        TryAlert(unit, "CD offensif")
    elseif HasBurstPotion(updateInfo) then
        TryAlert(unit, "potion de burst")
    end
end

local function WatchedUnits()
    local units = {}
    if IsInRaid() then
        for i = 1, 40 do
            local token = "raid" .. i
            if UnitExists(token) and not UnitIsUnit(token, "player") then
                units[#units + 1] = token
            end
        end
    else
        for i = 1, 4 do
            local token = "party" .. i
            if UnitExists(token) then units[#units + 1] = token end
        end
    end
    return units
end

-- Re-prime la baseline de tous les units sans alerter. Utilisé au démarrage
-- et quand les auraInstanceID sont re-randomisés (entrée M+, boss, PvP) :
-- sans ça, chaque aura déjà active redeviendrait "nouvelle".
local function RebaseAll()
    for token in pairs(watchFrames) do
        offensiveAuras[token] = BuildOffensiveSet(token)
    end
end

function PIReq_StartWatching()
    PIReq_StopWatching()

    local units = WatchedUnits()
    for _, token in ipairs(units) do
        offensiveAuras[token] = BuildOffensiveSet(token)
        local f = CreateFrame("Frame")
        f:RegisterUnitEvent("UNIT_AURA", token)
        f:SetScript("OnEvent", function(_, _, unit, updateInfo)
            OnUnitAura(unit, updateInfo)
        end)
        watchFrames[token] = f
    end

    if PIReq.debugMode then
        print("[PIReq] Watching " .. #units .. " unit(s) : IMPORTANT − (BIG_DEFENSIVE ∪ EXTERNAL_DEFENSIVE)")
    end
end

function PIReq_StopWatching()
    for token, f in pairs(watchFrames) do
        f:UnregisterAllEvents()
        f:SetScript("OnEvent", nil)
        watchFrames[token] = nil
    end
    alertCooldowns = {}
    offensiveAuras = {}
end

-- Diagnostic pour /pirequest scan : compte les auras par catégorie.
function PIReq_ScanUnit(token)
    local nImportant = #GetAuras(token, "HELPFUL|IMPORTANT")
    local nBigDef    = #GetAuras(token, "HELPFUL|BIG_DEFENSIVE")
    local nExtDef    = #GetAuras(token, "HELPFUL|EXTERNAL_DEFENSIVE")
    local offensive  = BuildOffensiveSet(token)
    local nOffensive = 0
    for _ in pairs(offensive) do nOffensive = nOffensive + 1 end
    return nImportant, nBigDef, nExtDef, nOffensive
end

-- Les auraInstanceID sont re-randomisés à l'entrée en M+, boss ou PvP
-- (12.0.5) : on rebase sans alerter pendant REBASE_WINDOW secondes.
local rebaseFrame = CreateFrame("Frame")
rebaseFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
rebaseFrame:RegisterEvent("ENCOUNTER_START")
pcall(rebaseFrame.RegisterEvent, rebaseFrame, "CHALLENGE_MODE_START")
pcall(rebaseFrame.RegisterEvent, rebaseFrame, "PVP_MATCH_ACTIVE")
rebaseFrame:SetScript("OnEvent", function(_, event)
    suppressUntil = GetTime() + REBASE_WINDOW
    RebaseAll()
    if PIReq.debugMode then print("[PIReq] rebase (" .. event .. ")") end
end)

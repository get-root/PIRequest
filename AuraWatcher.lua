-- PIRequest — AuraWatcher.lua
-- Côté prêtre : observe les auras IMPORTANT des coéquipiers via UNIT_AURA.
-- Blizzard classe nativement les gros CDs offensifs (Combustion, Témérité,
-- Dragonrage…) avec le filtre "HELPFUL|IMPORTANT".
-- Détection via C_UnitAuras.IsAuraFilteredOutByInstanceID (retourne false = match).

local DEDUP_WINDOW = 10  -- secondes entre deux alertes pour le même joueur

local alertCooldowns = {}  -- [unitToken] = timestamp
local watchFrames    = {}  -- [unitToken] = frame

-- Scanne les auras HELPFUL|IMPORTANT actives sur un unit.
-- Retourne true si au moins une est présente.
local function HasImportantAura(unit)
    local i = 1
    while true do
        local auraData = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL|IMPORTANT")
        if not auraData then break end
        if PIReq.debugMode then
            local ok, name = pcall(tostring, auraData.name)
            print("[PIReq] IMPORTANT aura sur " .. unit .. " : " .. (ok and name or "<tainted>"))
        end
        return true
        i = i + 1
    end
    return false
end

-- Vérifie si une aura ajoutée correspond au filtre HELPFUL|IMPORTANT.
local function IsImportantAura(unit, aura)
    if not aura.isHelpful then return false end
    if not aura.auraInstanceID then return false end
    -- IsAuraFilteredOutByInstanceID retourne false si l'aura CORRESPOND au filtre.
    local filtered = C_UnitAuras.IsAuraFilteredOutByInstanceID(
        unit, aura.auraInstanceID, "HELPFUL|IMPORTANT"
    )
    return filtered == false
end

local function TryAlert(unit)
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
        print("[PIReq] ALERTE → " .. unit .. " (" .. name .. ")")
    end
    PIReq_Highlight(name)
end

local function OnUnitAura(unit, updateInfo)
    if unit == "player" then return end

    if updateInfo and updateInfo.isFullUpdate then
        -- Full update : pas d'addedAuras, on scanne directement.
        if HasImportantAura(unit) then
            TryAlert(unit)
        end
        return
    end

    if not updateInfo or not updateInfo.addedAuras then return end

    for _, aura in ipairs(updateInfo.addedAuras) do
        if IsImportantAura(unit, aura) then
            if PIReq.debugMode then
                local ok, name = pcall(tostring, aura.name)
                print("[PIReq] IMPORTANT ajouté sur " .. unit
                    .. " : " .. (ok and name or "<tainted>"))
            end
            TryAlert(unit)
            return  -- Une alerte par event suffit
        end
    end
end

function PIReq_StartWatching()
    PIReq_StopWatching()

    local units = {}
    if IsInRaid() then
        for i = 1, 40 do units[#units + 1] = "raid" .. i end
    else
        for i = 1, 4 do units[#units + 1] = "party" .. i end
    end

    for _, token in ipairs(units) do
        local f = CreateFrame("Frame")
        f:RegisterUnitEvent("UNIT_AURA", token)
        f:SetScript("OnEvent", function(self, event, unit, updateInfo)
            OnUnitAura(unit, updateInfo)
        end)
        watchFrames[token] = f
    end

    if PIReq.debugMode then
        print("[PIReq] Watching " .. #units .. " units pour auras IMPORTANT.")
    end
end

function PIReq_StopWatching()
    for token, f in pairs(watchFrames) do
        f:UnregisterAllEvents()
        watchFrames[token] = nil
    end
    alertCooldowns = {}
end

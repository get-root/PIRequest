-- PIRequest — AuraWatcher.lua
-- Côté prêtre : observe les auras IMPORTANT des coéquipiers via UNIT_AURA.

local DEDUP_WINDOW = 10  -- secondes entre deux alertes pour le même joueur

local alertCooldowns     = {}  -- [unitToken] = timestamp
local watchFrames        = {}  -- [unitToken] = frame
local knownImportantUnits = {} -- [unitToken] = true si l'unit avait déjà une aura IMPORTANT

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
        i = i + 1
    end
    return i > 1
end

-- Vérifie si une aura ajoutée correspond au filtre HELPFUL|IMPORTANT.
local function IsImportantAura(unit, aura)
    if not aura.auraInstanceID then return false end
    -- IsAuraFilteredOutByInstanceID retourne false si l'aura CORRESPOND au filtre.
    -- Pour les joueurs cross-realm, Blizzard renvoie une "secret value" (ni true ni false) :
    -- on la traite comme un match plutôt que de rater l'alerte.
    local filtered = C_UnitAuras.IsAuraFilteredOutByInstanceID(
        unit, aura.auraInstanceID, "HELPFUL|IMPORTANT"
    )
    if filtered == false or issecretvalue(filtered) then return true end
    -- Validation secondaire via C_Spell.IsSpellImportant (si spellId disponible).
    if aura.spellId and C_Spell and C_Spell.IsSpellImportant then
        local imp = C_Spell.IsSpellImportant(aura.spellId)
        if imp == true or issecretvalue(imp) then return true end
    end
    return false
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
        -- Full update (zone transition, reload, unit apparaît à portée) :
        -- on n'alerte que si l'unit passe d'un état sans aura IMPORTANT à avec.
        local hasNow = HasImportantAura(unit)
        local hadBefore = knownImportantUnits[unit]
        knownImportantUnits[unit] = hasNow or nil
        if hasNow and not hadBefore then
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
            knownImportantUnits[unit] = true
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

    -- Baseline : unités déjà porteuses d'une aura IMPORTANT au moment du watch.
    -- Utilisé pour éviter les faux positifs sur isFullUpdate (zone-in, reload).
    for _, token in ipairs(units) do
        if UnitExists(token) and HasImportantAura(token) then
            knownImportantUnits[token] = true
        end
    end

    for _, token in ipairs(units) do
        if not watchFrames[token] then
            local f = CreateFrame("Frame")
            f:RegisterUnitEvent("UNIT_AURA", token)
            f:SetScript("OnEvent", function(self, event, unit, updateInfo)
                OnUnitAura(unit, updateInfo)
            end)
            watchFrames[token] = f
        end
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
    alertCooldowns      = {}
    knownImportantUnits = {}
end

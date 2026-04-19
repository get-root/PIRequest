-- PIRequest — AuraWatcher.lua
-- Côté prêtre : observe les auras IMPORTANT des coéquipiers via UNIT_AURA.
-- Blizzard classe nativement les gros CDs offensifs (Combustion, Témérité,
-- Dragonrage…) avec classification="important". Pas besoin de liste de spell IDs.

local DEDUP_WINDOW = 10  -- secondes entre deux alertes pour le même joueur

local alertCooldowns = {}  -- [unitToken] = timestamp
local watchFrames    = {}  -- [unitToken] = frame

local function OnUnitAura(unit, updateInfo)
    if unit == "player" then return end
    if not updateInfo or not updateInfo.addedAuras then return end

    for _, aura in ipairs(updateInfo.addedAuras) do
        if aura.isHelpful and aura.classification == "important" then
            local now = GetTime()
            local last = alertCooldowns[unit]
            if last and (now - last) < DEDUP_WINDOW then
                if PIReq.debugMode then
                    print("[PIReq] AURA ignorée (dédup " .. string.format("%.1f", now - last) .. "s) sur " .. unit)
                end
                return
            end
            alertCooldowns[unit] = now

            local name = Ambiguate(GetUnitName(unit, true) or "", "short")
            if PIReq.debugMode then
                print("[PIReq] AURA IMPORTANT détectée sur " .. unit .. " (" .. name .. ")")
            end
            PIReq_Highlight(name)
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

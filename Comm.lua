-- PIRequest — Comm.lua
-- Envoi et réception des messages addon.

local ADDON_NAME  = "PIRequest"
local DEDUP_WINDOW = 10  -- secondes

PIReq.requestCooldowns = {}  -- [senderName] = timestamp

-- Détermine le canal de broadcast selon le contexte.
-- En M+, le groupe est un "instance group" → canal INSTANCE_CHAT.
local function GroupChannel()
    if IsInRaid() then return "RAID" end
    if IsInRaid(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInGroup() then return "PARTY" end
    return nil
end

-- Prêtre → broadcast sa présence au groupe.
function PIReq_BroadcastHello()
    local channel = GroupChannel()
    if not channel then return end

    local _, class = UnitClass("player")
    if class ~= "PRIEST" then return end

    local spec = GetSpecialization()
    local specTag = (spec == 1) and "DISC" or "HOLY"

    C_ChatInfo.SendAddonMessage(ADDON_NAME, "HELLO:" .. specTag, channel)
end

-- Réception des messages addon.
local commFrame = CreateFrame("Frame")
commFrame:RegisterEvent("CHAT_MSG_ADDON")

-- Appelée par Core.lua pour re-register event + prefix après CHALLENGE_MODE_START.
function PIReq_ReregisterComm()
    C_ChatInfo.RegisterAddonMessagePrefix(ADDON_NAME)
    commFrame:RegisterEvent("CHAT_MSG_ADDON")
end
commFrame:SetScript("OnEvent", function(self, event, prefix, message, channel, sender)
    if PIReq.debugMode then
        print("[PIReq] ADDON MSG reçu: prefix=" .. tostring(prefix) .. " chan=" .. tostring(channel))
    end
    if prefix ~= ADDON_NAME then return end

    -- Normalise le nom de l'expéditeur (supprime le realm si même realm).
    local senderName = Ambiguate(sender, "short")

    if message == "HELLO:HOLY" or message == "HELLO:DISC" then
        -- Côté DPS : enregistre le prêtre.
        if PIReq.isPriest then return end
        local spec = (message == "HELLO:DISC") and "DISC" or "HOLY"
        PIReq.knownPriests[senderName] = { spec = spec, inGroup = true }
    end
end)

-- Réception des yells côté prêtre (CHAT_MSG_ADDON bloqué en M+ Midnight).
local yellFrame = CreateFrame("Frame")
yellFrame:RegisterEvent("CHAT_MSG_YELL")
yellFrame:SetScript("OnEvent", function(self, event, message, sender)
    if not PIReq.isPriest then return end
    if message ~= "." then return end

    local senderName = Ambiguate(sender, "short")
    if PIReq.debugMode then print("[PIReq] YELL reçu de " .. senderName) end

    -- Vérifie que l'expéditeur est bien dans le groupe.
    if not PIReq_IsNameInGroup(senderName) then
        if PIReq.debugMode then print("[PIReq] YELL ignoré : " .. senderName .. " pas dans le groupe") end
        return
    end

    -- Déduplication.
    local now = GetTime()
    local last = PIReq.requestCooldowns[senderName]
    if last and (now - last) < DEDUP_WINDOW then
        if PIReq.debugMode then print("[PIReq] YELL bloqué : dédup (" .. string.format("%.1f", now - last) .. "s)") end
        return
    end
    PIReq.requestCooldowns[senderName] = now

    PIReq_Highlight(senderName)
end)

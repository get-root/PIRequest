-- PIRequest — Comm.lua
-- Envoi et réception des messages addon.

local ADDON_NAME  = "PIRequest"
local DEDUP_WINDOW = 10  -- secondes

PIReq.requestCooldowns = {}  -- [senderName] = timestamp

-- Détermine le canal de broadcast selon le contexte (M+ ou Raid).
local function GroupChannel()
    if IsInRaid() then return "RAID" end
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
commFrame:SetScript("OnEvent", function(self, event, prefix, message, channel, sender)
    if prefix ~= ADDON_NAME then return end

    -- Normalise le nom de l'expéditeur (supprime le realm si même realm).
    local senderName = Ambiguate(sender, "short")

    if message == "HELLO:HOLY" or message == "HELLO:DISC" then
        -- Côté DPS : enregistre le prêtre.
        if PIReq.isPriest then return end
        local spec = (message == "HELLO:DISC") and "DISC" or "HOLY"
        PIReq.knownPriests[senderName] = { spec = spec, inGroup = true }

    elseif message == "REQUEST" then
        -- Côté prêtre : traite la requête.
        if not PIReq.isPriest then return end

        -- Double vérification : l'expéditeur est bien dans le groupe.
        if not UnitInParty(senderName) and not UnitInRaid(senderName) then return end

        -- Déduplication.
        local now = GetTime()
        local last = PIReq.requestCooldowns[senderName]
        if last and (now - last) < DEDUP_WINDOW then return end
        PIReq.requestCooldowns[senderName] = now

        -- Déclenche le highlight.
        PIReq_Highlight(senderName)
    end
end)

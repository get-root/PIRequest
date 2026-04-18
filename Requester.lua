-- PIRequest — Requester.lua
-- Logique côté DPS : envoi de la requête PI et feedback local.

PIReq.knownPriests = {}

-- Purge les prêtres qui ne sont plus dans le groupe.
function PIReq_PurgePriests()
    for name, data in pairs(PIReq.knownPriests) do
        if not UnitInParty(name) and not UnitInRaid(name) then
            PIReq.knownPriests[name] = nil
        end
    end
end

-- Appelée par la macro DPS : /run PIReq_SendRequest()
function PIReq_SendRequest()
    if PIReq.isPriest then return end  -- Un prêtre ne se demande pas une PI à lui-même.

    -- Cherche un prêtre valide dans le registre.
    local target = nil
    for name, data in pairs(PIReq.knownPriests) do
        if UnitInParty(name) or UnitInRaid(name) then
            target = name
            break
        end
    end

    if not target then
        -- Feedback local si aucun prêtre connu.
        print("|cffff6600[PIRequest]|r Aucun prêtre heal détecté dans le groupe.")
        return
    end

    C_ChatInfo.SendAddonMessage("PIRequest", "REQUEST", "WHISPER", target)
    print("|cff00ff00[PIRequest]|r Requête PI envoyée à " .. target .. ".")
end

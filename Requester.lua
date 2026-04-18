-- PIRequest — Requester.lua
-- Logique côté DPS : envoi de la requête PI et feedback local.

PIReq.knownPriests = {}

-- Retourne true si `name` est dans le groupe courant.
-- Utilise une plage fixe car GetNumGroupMembers() retourne 0 en instance group (M+).
local function IsNameInGroup(name)
    local maxMembers = IsInRaid() and 40 or 4
    for i = 1, maxMembers do
        local token = IsInRaid() and ("raid" .. i) or ("party" .. i)
        if UnitExists(token) then
            local n = Ambiguate(GetUnitName(token, true) or "", "short")
            if n == name then return true end
        end
    end
    return false
end

-- Purge les prêtres qui ne sont plus dans le groupe.
function PIReq_PurgePriests()
    for name in pairs(PIReq.knownPriests) do
        if not IsNameInGroup(name) then
            PIReq.knownPriests[name] = nil
        end
    end
end

-- Appelée par la macro DPS : /run PIReq_SendRequest()
function PIReq_SendRequest()
    if PIReq.isPriest then return end  -- Un prêtre ne se demande pas une PI à lui-même.

    -- Cherche un prêtre valide dans le registre.
    local target = nil
    for name in pairs(PIReq.knownPriests) do
        if IsNameInGroup(name) then
            target = name
            break
        end
    end

    if not target then
        -- Feedback local si aucun prêtre connu.
        print("|cffff6600[PIRequest]|r Aucun prêtre heal détecté dans le groupe.")
        return
    end

    -- Canal PARTY pour compatibilité M+ (WHISPER addon bloqué en challenge mode).
    -- Le nom du prêtre cible est embarqué dans le message.
    local channel = IsInRaid() and "RAID" or "PARTY"
    C_ChatInfo.SendAddonMessage("PIRequest", "REQUEST:" .. target, channel)
    print("|cff00ff00[PIRequest]|r Requête PI envoyée à " .. target .. ".")
end

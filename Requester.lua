-- PIRequest — Requester.lua
-- Logique côté DPS : envoi de la requête PI et feedback local.

PIReq.knownPriests  = {}
PIReq.lastSendTime  = 0

local DEDUP_WINDOW = 10  -- secondes entre deux yells DPS

-- Retourne true si `name` est dans le groupe courant.
-- Utilise une plage fixe car GetNumGroupMembers() retourne 0 en instance group (M+).
-- Exposée en globale pour être utilisable dans Comm.lua.
function PIReq_IsNameInGroup(name)
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
        if not PIReq_IsNameInGroup(name) then
            PIReq.knownPriests[name] = nil
        end
    end
end

-- Appelée par la macro DPS : /run PIReq_SendRequest()
function PIReq_SendRequest()
    if PIReq.isPriest then return end  -- Un prêtre ne se demande pas une PI à lui-même.

    -- Déduplication côté DPS pour éviter le flood yell en cas de spam macro.
    local now = GetTime()
    if now - PIReq.lastSendTime < DEDUP_WINDOW then return end

    -- Cherche un prêtre valide dans le registre.
    local target = nil
    for name in pairs(PIReq.knownPriests) do
        if PIReq_IsNameInGroup(name) then
            target = name
            break
        end
    end

    if not target then
        -- Feedback local si aucun prêtre connu.
        print("|cffff6600[PIRequest]|r Aucun prêtre heal détecté dans le groupe.")
        return
    end

    -- Envoie un yell "." — CHAT_MSG_ADDON étant bloqué en M+ Midnight.
    -- Le prêtre écoute CHAT_MSG_YELL et identifie le demandeur via sender.
    SendChatMessage(".", "YELL")
    PIReq.lastSendTime = now
    print("|cff00ff00[PIRequest]|r Requête PI envoyée à " .. target .. ".")
end

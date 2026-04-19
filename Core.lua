-- PIRequest — Core.lua
-- Initialisation, détection du rôle, frame d'événements principal.

PIReq = {}
PIReq.isPriest = false

local ADDON_NAME = "PIRequest"

local function IsPriestHealer()
    local _, class = UnitClass("player")
    if class ~= "PRIEST" then return false end
    local spec = GetSpecialization()
    return spec == 1 or spec == 2  -- 1 = Discipline, 2 = Holy
end

local function OnRoleUpdate()
    PIReq.isPriest = IsPriestHealer()
    if PIReq.isPriest then
        PIReq_BroadcastHello()
    else
        PIReq_PurgePriests()
    end
end

local coreFrame = CreateFrame("Frame")
coreFrame:RegisterEvent("ADDON_LOADED")
coreFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
coreFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
coreFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
coreFrame:RegisterEvent("CHALLENGE_MODE_START")
coreFrame:RegisterEvent("PLAYER_REGEN_DISABLED")

coreFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        C_ChatInfo.RegisterAddonMessagePrefix(ADDON_NAME)

        SLASH_PIREQUEST1 = "/pirequest"
        SlashCmdList["PIREQUEST"] = function(msg)
            local cmd = strtrim(msg):lower()
            if cmd == "test" then
                local name = UnitName("player")
                print("|cff00ff00[PIRequest]|r Test notification → " .. name)
                PIReq_Highlight(name)
            elseif cmd == "status" then
                print("|cff00ff00[PIRequest]|r isPriest=" .. tostring(PIReq.isPriest)
                    .. "  spec=" .. tostring(GetSpecialization()))
            elseif cmd == "testdps" then
                -- Envoie directement un yell "." sans vérifier le registre des prêtres.
                -- Permet de tester la mécanique yell même sans prêtre dans le groupe.
                local now = GetTime()
                if now - (PIReq.lastSendTime or 0) < 10 then
                    print("|cffff6600[PIRequest]|r Test DPS : cooldown actif, attends " .. string.format("%.0f", 10 - (now - PIReq.lastSendTime)) .. "s.")
                else
                    SendChatMessage(".", "YELL")
                    PIReq.lastSendTime = now
                    print("|cff00ff00[PIRequest]|r Test DPS : yell envoyé.")
                end
            elseif cmd == "joinchan" then
                -- TEST canal custom : rejoint le canal "PIRequest".
                JoinChannelByName("PIRequest")
                local num = GetChannelName("PIRequest")
                if num and num > 0 then
                    print("|cff00ffff[PIReq-ChanTest]|r Canal PIRequest rejoint (n°" .. num .. ").")
                else
                    print("|cffff6600[PIReq-ChanTest]|r Canal PIRequest introuvable après join.")
                end
            elseif cmd == "chantest" then
                -- TEST canal custom : envoie un message de test dans le canal "PIRequest".
                local num = GetChannelName("PIRequest")
                if not num or num == 0 then
                    print("|cffff6600[PIReq-ChanTest]|r Canal PIRequest introuvable. Fais /pirequest joinchan d'abord.")
                else
                    SendChatMessage("CHAN_TEST", "CHANNEL", nil, num)
                    print("|cff00ffff[PIReq-ChanTest]|r Message envoyé sur le canal n°" .. num .. ".")
                end
            elseif cmd == "debug" then
                PIReq.debugMode = not PIReq.debugMode
                print("|cff00ff00[PIRequest]|r Debug " .. (PIReq.debugMode and "ON" or "OFF"))
            else
                print("|cff00ff00[PIRequest]|r Commandes : /pirequest test | testdps | joinchan | chantest | status | debug")
            end
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        C_ChatInfo.RegisterAddonMessagePrefix(ADDON_NAME)
        OnRoleUpdate()

    elseif event == "CHALLENGE_MODE_START" then
        -- WoW purge les registrations après avoir lancé cet event.
        -- On re-register en différé (frame suivante) pour passer après le nettoyage.
        C_Timer.After(0, function()
            PIReq_ReregisterComm()
            OnRoleUpdate()
        end)

    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Filet de sécurité : re-register au premier combat (début de clé).
        PIReq_ReregisterComm()

    elseif event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "GROUP_ROSTER_UPDATE" then
        OnRoleUpdate()
    end
end)

-- TEST : écoute les messages du canal custom "PIRequest".
local chanTestFrame = CreateFrame("Frame")
chanTestFrame:RegisterEvent("CHAT_MSG_CHANNEL")
chanTestFrame:SetScript("OnEvent", function(self, event, message, sender, _, _, _, _, _, chanName)
    if chanName ~= "PIRequest" then return end
    local senderName = Ambiguate(sender, "short")
    print("|cff00ffff[PIReq-ChanTest]|r Reçu de " .. senderName .. " : " .. message)
end)

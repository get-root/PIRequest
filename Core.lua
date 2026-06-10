-- PIRequest — Core.lua
-- Initialisation, détection du rôle, frame d'événements principal.

PIReq = {}
PIReq.isPriest     = false
PIReq.enabled      = true
PIReq.soundEnabled = true

local ADDON_NAME = "PIRequest"

local function IsPriestHealer()
    local _, class = UnitClass("player")
    if class ~= "PRIEST" then return false end
    local spec = GetSpecialization()
    return spec == 1 or spec == 2  -- 1 = Discipline, 2 = Holy
end

local function OnRoleUpdate()
    PIReq.isPriest = IsPriestHealer()
    if PIReq.isPriest and PIReq.enabled then
        PIReq_StartWatching()
    else
        PIReq_StopWatching()
    end
end

local coreFrame = CreateFrame("Frame")
coreFrame:RegisterEvent("ADDON_LOADED")
coreFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
coreFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
coreFrame:RegisterEvent("GROUP_ROSTER_UPDATE")

coreFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end

        print("|cff00ff00[PIRequest]|r chargé. isPriest=" .. tostring(IsPriestHealer()))

        SLASH_PIREQUEST1 = "/pirequest"
        SlashCmdList["PIREQUEST"] = function(msg)
            local cmd = strtrim(msg):lower()
            if cmd == "test" then
                local name = UnitName("player")
                print("|cff00ff00[PIRequest]|r Test notification → " .. name)
                PIReq_Highlight(name)
            elseif cmd == "status" then
                print("|cff00ff00[PIRequest]|r isPriest=" .. tostring(PIReq.isPriest)
                    .. "  spec=" .. tostring(GetSpecialization())
                    .. "  enabled=" .. tostring(PIReq.enabled))
            elseif cmd == "scan" then
                -- Compte les auras par catégorie pour chaque membre du groupe.
                -- "offensif" = IMPORTANT − (BIG_DEFENSIVE ∪ EXTERNAL_DEFENSIVE),
                -- c'est ce qui déclenche l'alerte.
                local found = false
                local maxMembers = IsInRaid() and 40 or 4
                for i = 1, maxMembers do
                    local token = IsInRaid() and ("raid" .. i) or ("party" .. i)
                    if UnitExists(token) and not UnitIsUnit(token, "player") then
                        local name = Ambiguate(GetUnitName(token, true) or "", "short")
                        local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(token) or "?"
                        local nImp, nBigDef, nExtDef, nOff = PIReq_ScanUnit(token)
                        print(string.format(
                            "|cff00ff00[PIRequest]|r %s = %s (%s) : important=%d  bigDef=%d  extDef=%d  → |cffffd700offensif=%d|r",
                            token, name, role, nImp, nBigDef, nExtDef, nOff))
                        found = true
                    end
                end
                if not found then
                    print("|cffff6600[PIRequest]|r Aucun membre de groupe trouvé.")
                end
            elseif cmd == "toggle" or cmd == "enable" or cmd == "disable" then
                if cmd == "enable" then
                    PIReq.enabled = true
                elseif cmd == "disable" then
                    PIReq.enabled = false
                else
                    PIReq.enabled = not PIReq.enabled
                end
                if PIReq.enabled then
                    print("|cff00ff00[PIRequest]|r Alertes |cff00ff00activées|r.")
                    if PIReq.isPriest then PIReq_StartWatching() end
                else
                    print("|cff00ff00[PIRequest]|r Alertes |cffff6600désactivées|r.")
                    PIReq_StopWatching()
                end
            elseif cmd == "debug" then
                PIReq.debugMode = not PIReq.debugMode
                print("|cff00ff00[PIRequest]|r Debug " .. (PIReq.debugMode and "ON" or "OFF"))
            elseif cmd == "sound" then
                PIReq.soundEnabled = not PIReq.soundEnabled
                print("|cff00ff00[PIRequest]|r Son " .. (PIReq.soundEnabled and "ON" or "OFF"))
            else
                print("|cff00ff00[PIRequest]|r Commandes : /pirequest test | scan | status | debug | sound | toggle | enable | disable")
            end
        end

    elseif event == "PLAYER_ENTERING_WORLD"
        or event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "GROUP_ROSTER_UPDATE" then
        OnRoleUpdate()
    end
end)

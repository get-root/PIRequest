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
                    .. "  spec=" .. tostring(GetSpecialization()))
            elseif cmd == "scan" then
                -- Scanne manuellement les membres du groupe pour auras IMPORTANT.
                local found = false
                local maxMembers = IsInRaid() and 40 or 4
                for i = 1, maxMembers do
                    local token = IsInRaid() and ("raid" .. i) or ("party" .. i)
                    if UnitExists(token) then
                        local name = Ambiguate(GetUnitName(token, true) or "", "short")
                        print("|cff00ff00[PIRequest]|r scan " .. token .. " = " .. name)
                        local j = 1
                        while true do
                            local ok, auraData = pcall(C_UnitAuras.GetAuraDataByIndex, token, j, "HELPFUL|IMPORTANT")
                            if not ok or not auraData then break end
                            local okN, aName = pcall(tostring, auraData.name)
                            print("  → IMPORTANT : " .. (okN and aName or "<tainted>"))
                            j = j + 1
                        end
                        found = true
                    end
                end
                if not found then
                    print("|cffff6600[PIRequest]|r Aucun membre de groupe trouvé.")
                end
            elseif cmd == "debug" then
                PIReq.debugMode = not PIReq.debugMode
                print("|cff00ff00[PIRequest]|r Debug " .. (PIReq.debugMode and "ON" or "OFF"))
            else
                print("|cff00ff00[PIRequest]|r Commandes : /pirequest test | scan | status | debug")
            end
        end

    elseif event == "PLAYER_ENTERING_WORLD"
        or event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "GROUP_ROSTER_UPDATE" then
        OnRoleUpdate()
    end
end)

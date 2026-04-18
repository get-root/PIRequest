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
            elseif cmd == "debug" then
                PIReq.debugMode = not PIReq.debugMode
                print("|cff00ff00[PIRequest]|r Debug " .. (PIReq.debugMode and "ON" or "OFF"))
            else
                print("|cff00ff00[PIRequest]|r Commandes : /pirequest test | status | debug")
            end
        end

    elseif event == "PLAYER_ENTERING_WORLD"
        or event == "CHALLENGE_MODE_START" then
        C_ChatInfo.RegisterAddonMessagePrefix(ADDON_NAME)
        OnRoleUpdate()

    elseif event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "GROUP_ROSTER_UPDATE" then
        OnRoleUpdate()
    end
end)

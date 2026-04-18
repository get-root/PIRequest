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

local coreFrame = CreateFrame("Frame")
coreFrame:RegisterEvent("ADDON_LOADED")
coreFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
coreFrame:RegisterEvent("GROUP_ROSTER_UPDATE")

coreFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        C_ChatInfo.RegisterAddonMessagePrefix(ADDON_NAME)

    elseif event == "PLAYER_ENTERING_WORLD" then
        PIReq.isPriest = IsPriestHealer()
        if PIReq.isPriest then
            PIReq_BroadcastHello()
        else
            PIReq_PurgePriests()
        end

    elseif event == "GROUP_ROSTER_UPDATE" then
        PIReq.isPriest = IsPriestHealer()
        if PIReq.isPriest then
            PIReq_BroadcastHello()
        else
            PIReq_PurgePriests()
        end
    end
end)

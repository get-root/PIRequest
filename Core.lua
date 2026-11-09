-- PIRequest — Core.lua
-- Init, SavedVariables, détection du rôle, helpers partagés, slash commands.
--
-- Deux modes de détection selon que les auras sont "secrètes" (12.1) :
--   * lisibles (monde ouvert hors combat…)   → AuraWatcher.lua (Lua lit le spellId)
--   * secrètes (combat, boss, M+, PvP)       → Engine.lua (sons + icônes gérés
--     par le moteur, filtrés par spellId, sans que Lua ne lise quoi que ce soit)

PIReq = PIReq or {}
PIReq.isPriest   = false
PIReq.debugMode  = false
PIReq.spellSet   = {}      -- [spellId] = true : auras qui déclenchent l'alerte
PIReq.nameCache  = {}      -- [unit] = dernier nom lisible

local ADDON_NAME = "PIRequest"
local issecret   = issecretvalue or function() return false end

local DEFAULTS = {
    enabled      = true,
    sound        = true,
    soundKey     = "raidwarning", -- clé de PIReq.SOUNDS, ou "custom"
    soundCustom  = nil,    -- FileDataID si soundKey == "custom"
    tracker      = true,   -- icônes moteur (mode secret)
    hideOnCooldown = true, -- pas d'alerte pendant la recharge de Power Infusion
    priorityOnly = false,  -- seulement les CDs ★ (priorité haute)
    filterByName = false,  -- limiter aux personnages de `names`
    names        = {},     -- { "Nom1", "Nom2" }
    spells       = {},     -- [spellId] = true/false (surcharge du défaut)
    custom       = {},     -- [spellId] = true (IDs ajoutés à la main)
}

local function print_(msg) print("|cff00ff00[PIRequest]|r " .. msg) end
PIReq.Print = print_

-- ---------------------------------------------------------------------------
-- État "auras secrètes" (donjon/boss/PvP/combat)
-- ---------------------------------------------------------------------------

-- Requête officielle Blizzard ; sonde de secours si l'API est absente.
-- Une réponse illisible est traitée comme "restreint" (le plus prudent).
function PIReq.IsRestricted()
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local ok, r = pcall(C_Secrets.ShouldAurasBeSecret)
        if ok then
            if issecret(r) then return true end
            return r == true
        end
    end
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        return not pcall(C_UnitAuras.GetAuraDataByIndex, "player", 1, "HELPFUL")
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Unités / noms / rôles
-- ---------------------------------------------------------------------------

-- Nom court d'une unité. Peut être secret dans certains contextes : on garde
-- alors le dernier nom lisible connu.
local function Readable(v)
    return type(v) == "string" and not issecret(v) and v ~= ""
end

-- "Unknown" = nom pas encore chargé (fréquent à l'entrée en raid) : à traiter
-- comme illisible, sinon le joueur filtré serait écarté définitivement.
-- Le cache est indexé par token MAIS validé par GUID, car les tokens raidN
-- changent d'occupant quand le roster est réorganisé.
function PIReq.UnitShortName(unit)
    local gok, guid = pcall(UnitGUID, unit)
    if not (gok and Readable(guid)) then guid = nil end

    local ok, n = pcall(GetUnitName, unit, true)
    if ok and Readable(n) and n ~= UNKNOWNOBJECT and n ~= "Unknown" then
        n = Ambiguate(n, "short")
        PIReq.nameCache[unit] = { name = n, guid = guid }
        return n
    end

    local c = PIReq.nameCache[unit]
    if c and guid and c.guid == guid then return c.name end
    return nil
end

local function NameFilterActive()
    local db = PIReq.DB
    return db and db.filterByName and #db.names > 0
end
PIReq.NameFilterActive = NameFilterActive

local function NameAllowed(unit)
    if not NameFilterActive() then return true end
    local n = PIReq.UnitShortName(unit)
    if not n then return false end
    n = n:lower()
    for _, wanted in ipairs(PIReq.DB.names) do
        if wanted:lower() == n then return true end
    end
    return false
end

-- Rôle inconnu = on surveille quand même. Un filtre par nom explicite prime
-- sur le rôle (l'utilisateur a choisi ce personnage).
local function RoleAllowed(unit)
    if NameFilterActive() then return true end
    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
    if role == nil or issecret(role) then return true end
    return role ~= "HEALER" and role ~= "TANK"
end

function PIReq.IsUnitTracked(unit)
    return UnitExists(unit) and NameAllowed(unit) and RoleAllowed(unit)
end

-- Units du groupe (hors joueur) qui passent les filtres.
function PIReq.TrackedUnits()
    local units = {}
    if IsInRaid() then
        for i = 1, 40 do
            local token = "raid" .. i
            if UnitExists(token) and not UnitIsUnit(token, "player") and PIReq.IsUnitTracked(token) then
                units[#units + 1] = token
            end
        end
    else
        for i = 1, 4 do
            local token = "party" .. i
            if UnitExists(token) and PIReq.IsUnitTracked(token) then
                units[#units + 1] = token
            end
        end
    end
    return units
end

-- ---------------------------------------------------------------------------
-- Recharge de Power Infusion : pas d'alerte inutile quand PI n'est pas dispo
-- ---------------------------------------------------------------------------

local PI_SPELL_ID  = 10060
local PI_COOLDOWN  = 120   -- secondes (2 min), utilisé si la vraie durée est illisible
local piReadyAt    = 0

function PIReq.PIOnCooldown()
    return GetTime() < piReadyAt
end

function PIReq.AlertsMuted()
    return PIReq.DB and PIReq.DB.hideOnCooldown and PIReq.PIOnCooldown() or false
end

-- Units réellement surveillées maintenant (aucune pendant la recharge de PI).
function PIReq.ActiveUnits()
    if PIReq.AlertsMuted() then return {} end
    return PIReq.TrackedUnits()
end

local function ScheduleReady(delay)
    C_Timer.After(delay + 0.2, function()
        if GetTime() >= piReadyAt then PIReq.Refresh() end  -- PI de nouveau dispo : on réarme
    end)
end

-- Relit la vraie recharge (/reload en pleine recharge). Les champs peuvent être
-- secrets en combat : dans ce cas on ne touche à rien.
local function SyncPICooldown()
    if not (C_Spell and C_Spell.GetSpellCooldown) then return end
    local ok, info = pcall(C_Spell.GetSpellCooldown, PI_SPELL_ID)
    if not ok or type(info) ~= "table" or issecret(info) then return end
    local start, dur = info.startTime, info.duration
    if issecret(start) or issecret(dur) or type(start) ~= "number" or type(dur) ~= "number" then return end
    if dur > 2 and start > 0 then               -- > GCD : vraie recharge
        piReadyAt = start + dur
        ScheduleReady(piReadyAt - GetTime())
    end
end

local function OnPICast()
    local dur = PI_COOLDOWN
    if C_Spell and C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, PI_SPELL_ID)
        if ok and type(info) == "table" and not issecret(info) then
            local d = info.duration
            if type(d) == "number" and not issecret(d) and d > 2 then dur = d end
        end
    end
    piReadyAt = GetTime() + dur
    if PIReq.debugMode then PIReq.Print(string.format("PI lancée : alertes coupées %ds", dur)) end
    PIReq.Refresh()
    ScheduleReady(dur)
end

-- ---------------------------------------------------------------------------
-- Son d'alerte
-- ---------------------------------------------------------------------------

-- Retourne (soundKit, fileDataID) du son choisi. Le son personnalisé n'a qu'un
-- FileDataID (kit = nil).
function PIReq.GetSound()
    local db = PIReq.DB
    if db.soundKey == "custom" and tonumber(db.soundCustom) then
        return nil, tonumber(db.soundCustom)
    end
    for _, s in ipairs(PIReq.SOUNDS) do
        if s.key == db.soundKey then return s.kit, s.file end
    end
    local d = PIReq.SOUNDS[1]
    return d.kit, d.file
end

function PIReq.PlayAlertSound()
    local kit, file = PIReq.GetSound()
    if kit then PlaySound(kit, "Master")
    elseif file then PlaySoundFile(file, "Master") end
end

-- ---------------------------------------------------------------------------
-- Sorts sélectionnés
-- ---------------------------------------------------------------------------

function PIReq.IsEntryEnabled(entry)
    local o = PIReq.DB.spells[entry.id]
    if o ~= nil then return o end
    return entry.default ~= false
end

function PIReq.RebuildSpellSet()
    local set = {}
    for _, entry in ipairs(PIReq.SPELLS) do
        local prioOk = not PIReq.DB.priorityOnly or entry.priority or entry.class == "POTION"
        if prioOk and PIReq.IsEntryEnabled(entry) then
            set[entry.id] = true
            for _, alt in ipairs(entry.alts or {}) do set[alt] = true end
        end
    end
    for id, on in pairs(PIReq.DB.custom) do
        if on then set[id] = true end
    end
    PIReq.spellSet = set
end

-- À appeler après tout changement de configuration (options, slash).
function PIReq.ApplyConfig()
    PIReq.RebuildSpellSet()
    PIReq.Refresh()
end

-- ---------------------------------------------------------------------------
-- Rôle du joueur et (re)démarrage des modules
-- ---------------------------------------------------------------------------

local function IsPriestHealer()
    local _, class = UnitClass("player")
    if class ~= "PRIEST" then return false end
    local spec = GetSpecialization()
    return spec == 1 or spec == 2  -- 1 = Discipline, 2 = Holy
end

function PIReq.Refresh()
    if not PIReq.DB then return end
    PIReq.isPriest = IsPriestHealer()
    if PIReq.isPriest and PIReq.DB.enabled then
        PIReq_StartWatching()
        PIReq_EngineSync()
        PIReq_PollerSync()
    else
        PIReq_StopWatching()
        PIReq_EngineStop()
        PIReq_PollerSync()
    end
end

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------

local function ParseNames(str)
    local names = {}
    for token in str:gmatch("[^,%s]+") do
        names[#names + 1] = Ambiguate(token, "short")
    end
    return names
end
PIReq.ParseNames = ParseNames

local function OnOff(b) return b and "|cff00ff00ON|r" or "|cffff6600OFF|r" end

local function HandleSlash(msg)
    local db = PIReq.DB
    local cmd, rest = strtrim(msg):match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()

    if cmd == "test" then
        local name = UnitName("player")
        print_("Test notification → " .. name)
        PIReq_Highlight(name, 10060, true)
        PIReq_TrackerPreview(5)

    elseif cmd == "status" then
        print_(string.format("isPriest=%s spec=%s enabled=%s sound=%s tracker=%s",
            tostring(PIReq.isPriest), tostring(GetSpecialization()),
            tostring(db.enabled), tostring(db.sound), tostring(db.tracker)))
        print_("auras secrètes maintenant : " .. tostring(PIReq.IsRestricted()))
        print_(string.format("masquer pendant recharge PI : %s (PI en recharge : %s)", tostring(db.hideOnCooldown), tostring(PIReq.PIOnCooldown())))
        if NameFilterActive() then
            print_("filtre par nom : " .. table.concat(db.names, ", "))
        else
            print_("filtre par nom : désactivé (tous les DPS)")
        end

    elseif cmd == "scan" then
        -- Diagnostic : ce que l'addon surveille réellement.
        local units = PIReq.ActiveUnits()
        local n = 0
        for _ in pairs(PIReq.spellSet) do n = n + 1 end
        print_(string.format("%d unit(s) surveillée(s), %d spellId(s) actifs, sons moteur=%d, icônes moteur=%d",
            #units, n, PIReq_EngineStats()))
        for _, u in ipairs(units) do
            print_("  " .. u .. " = " .. tostring(PIReq.UnitShortName(u)))
        end
        for _, line in ipairs(PIReq_EngineDebug()) do print_("  " .. line) end
        print_("Ascendance (114050/114051/1219480) actif : " ..
            tostring(PIReq.spellSet[114050] and PIReq.spellSet[114051] and PIReq.spellSet[1219480] or false))
        if NameFilterActive() and #units == 0 then
            -- Aide au diagnostic : montre ce que l'addon lit comme noms dans le groupe.
            print_("|cffff6600Aucun membre ne correspond au filtre|r (" .. table.concat(db.names, ", ") .. "). Noms lus :")
            local prefix, max = IsInRaid() and "raid" or "party", IsInRaid() and 40 or 4
            for i = 1, max do
                local t = prefix .. i
                if UnitExists(t) then
                    local ok, raw = pcall(GetUnitName, t, true)
                    print_(string.format("  %s : lu=%s  court=%s", t, tostring(ok and Readable(raw) and raw or "illisible"),
                        tostring(PIReq.UnitShortName(t))))
                end
            end
        end

    elseif cmd == "ctest" then
        local unit, flt = rest:match("^(%S*)%s*(%S*)$")
        PIReq_EngineContainerTest(unit, flt == "filtre")

    elseif cmd == "resync" then
        -- Relance la synchro moteur en affichant chaque étape (diagnostic).
        PIReq_EngineVerbose(true)
        PIReq.Refresh()
        PIReq_EngineVerbose(false)
        for _, line in ipairs(PIReq_EngineDebug()) do print_("  " .. line) end

    elseif cmd == "secrecy" then
        -- Pour chaque CD actif : l'aura est-elle secrète ? (détermine ce qui est détectable en combat)
        local names = { [0] = "jamais secrète", [1] = "toujours secrète", [2] = "secrète selon contexte" }
        local shown = 0
        for _, e in ipairs(PIReq.SPELLS) do
            if PIReq.spellSet[e.id] then
                local ok, lvl = pcall(C_Secrets.GetSpellAuraSecrecy, e.id)
                local ok2, now = pcall(C_Secrets.ShouldSpellAuraBeSecret, e.id)
                print_(string.format("  %s (%d) : %s — secrète maintenant=%s",
                    C_Spell.GetSpellName(e.id) or "?", e.id,
                    ok and names[lvl] or "API indisponible", ok2 and tostring(now) or "?"))
                shown = shown + 1
            end
        end
        if shown == 0 then print_("Aucun sort actif.") end

    elseif cmd == "only" then
        if rest == "" or rest:lower() == "off" then
            db.filterByName = false
            print_("Filtre par nom |cffff6600désactivé|r : tous les DPS.")
        else
            db.names = ParseNames(rest)
            db.filterByName = #db.names > 0
            print_("Filtre par nom : " .. table.concat(db.names, ", "))
        end
        PIReq.ApplyConfig()
        if PIReq.RefreshOptions then PIReq.RefreshOptions() end

    elseif cmd == "add" or cmd == "remove" then
        local id = tonumber(rest)
        if not id then print_("Usage : /pirequest " .. cmd .. " <spellId>") return end
        db.custom[id] = (cmd == "add") or nil
        print_((cmd == "add" and "Ajouté : " or "Retiré : ") .. id)
        PIReq.ApplyConfig()
        if PIReq.RefreshOptions then PIReq.RefreshOptions() end

    elseif cmd == "config" or cmd == "options" then
        PIReq_OpenOptions()

    elseif cmd == "tracker" then
        PIReq_ToggleTrackerUnlock()

    elseif cmd == "toggle" or cmd == "enable" or cmd == "disable" then
        if cmd == "enable" then db.enabled = true
        elseif cmd == "disable" then db.enabled = false
        else db.enabled = not db.enabled end
        print_("Alertes " .. OnOff(db.enabled))
        PIReq.Refresh()

    elseif cmd == "debug" then
        PIReq.debugMode = not PIReq.debugMode
        print_("Debug " .. OnOff(PIReq.debugMode))

    elseif cmd == "sound" then
        db.sound = not db.sound
        print_("Son " .. OnOff(db.sound))
        PIReq.Refresh()

    else
        print_("Commandes : config | test | status | scan | only <noms>|off | add <id> | remove <id> | secrecy | resync | ctest | tracker | sound | toggle | enable | disable | debug")
    end
end

-- ---------------------------------------------------------------------------
-- Événements
-- ---------------------------------------------------------------------------

local coreFrame = CreateFrame("Frame")
coreFrame:RegisterEvent("ADDON_LOADED")
coreFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
coreFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
coreFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
coreFrame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
coreFrame:RegisterEvent("UNIT_NAME_UPDATE")
coreFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")

local nameRetryPending = false

coreFrame:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- Fiable uniquement pour "player" (spellId lisible) : sert à détecter MON PI.
        if PIReq.DB and PIReq.isPriest and not issecret(arg3) and arg3 == PI_SPELL_ID then OnPICast() end
        return
    end
    if event == "UNIT_NAME_UPDATE" then
        -- Un nom de groupe vient de se charger : si un filtre par nom est actif,
        -- on reconstruit (debounce) pour intégrer le joueur qui manquait.
        if PIReq.DB and PIReq.isPriest and NameFilterActive() and not nameRetryPending
           and type(arg1) == "string" and (arg1:find("^raid%d") or arg1:find("^party%d")) then
            nameRetryPending = true
            C_Timer.After(1, function()
                nameRetryPending = false
                PIReq.Refresh()
            end)
        end
        return
    end
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end

        PIRequestDB = PIRequestDB or {}
        for k, v in pairs(DEFAULTS) do
            if PIRequestDB[k] == nil then
                PIRequestDB[k] = type(v) == "table" and CopyTable(v) or v
            end
        end
        PIReq.DB = PIRequestDB
        PIReq.RebuildSpellSet()

        SLASH_PIREQUEST1 = "/pirequest"
        SlashCmdList["PIREQUEST"] = HandleSlash
        print_("chargé. /pirequest config pour les options.")

    elseif PIReq.DB then
        if event == "PLAYER_ENTERING_WORLD" then SyncPICooldown() end
        PIReq.Refresh()
    end
end)

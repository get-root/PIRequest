-- PIRequest — Poller.lua
-- Détection EN COMBAT par sondage de C_UnitAuras.GetUnitAuraBySpellID.
--
-- Quand les auras sont secrètes, GetUnitAuraBySpellID(unit, spellId) reste
-- utilisable pour les auras que Blizzard classe non secrètes (argument marqué
-- RequiresNonSecretAura) : une aura présente renvoie une AuraData (lisible ou
-- secrète — on ne la lit jamais), une aura absente renvoie nil. Seule la
-- PRÉSENCE nous intéresse, et comme on interroge par spellId on sait lequel.
-- → vraie bannière + highlight en combat, en même temps que le son moteur.
--
-- Les sorts dont l'aura est secrète lèvent une erreur (pcall) : ils sont marqués
-- "non sondables" pour la durée de la restriction et restent couverts par le
-- seul son moteur. /pirequest secrecy liste ce qui est sondable.

local issecret = issecretvalue or function() return false end

local INTERVAL      = 0.25
local INTERVAL_SLOW = 0.5
local SLOW_ABOVE    = 400   -- unités × sorts

local state  = {}   -- [unit] = { [spellId] = bool }  (nil = pas encore amorcé)
local broken = {}   -- [spellId] = true : requête refusée (aura secrète)
local ticker, tickerInterval
local wasRestricted = false

-- true/false = présence ; nil = non interrogeable.
local function Present(unit, id)
    if broken[id] then return nil end
    local ok, aura = pcall(C_UnitAuras.GetUnitAuraBySpellID, unit, id)
    if not ok then
        broken[id] = true
        if PIReq.debugMode then PIReq.Print("sondage impossible (aura secrète) : " .. id) end
        return nil
    end
    if issecret(aura) then return true end   -- existe, contenu masqué
    return aura ~= nil
end

local function Tick()
    local restricted = PIReq.IsRestricted()
    if not restricted then
        -- Le chemin UNIT_AURA (AuraWatcher) gère les auras lisibles. On repart de
        -- zéro pour réamorcer silencieusement à la prochaine restriction.
        if wasRestricted then wipe(state); wipe(broken) end
        wasRestricted = false
        return
    end
    wasRestricted = true

    local units = PIReq.ActiveUnits()
    local keep = {}
    for _, unit in ipairs(units) do
        keep[unit] = true
        local st = state[unit]
        local primed = st ~= nil          -- 1er passage : on enregistre sans alerter
        if not st then st = {}; state[unit] = st end
        for id in pairs(PIReq.spellSet) do
            local now = Present(unit, id)
            if now ~= nil then
                if now and primed and not st[id] then
                    if PIReq.debugMode then PIReq.Print("sondage : " .. unit .. " a " .. id) end
                    PIReq.RaiseAlert(unit, id)
                end
                st[id] = now
            end
        end
    end
    for unit in pairs(state) do
        if not keep[unit] then state[unit] = nil end
    end
end

-- (Re)démarre ou arrête le sondage selon l'état courant.
function PIReq_PollerSync()
    wipe(state)
    if ticker then ticker:Cancel(); ticker = nil end
    if not (PIReq.DB and PIReq.isPriest and PIReq.DB.enabled) then return end
    if not (C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID) then return end

    local n = 0
    for _ in pairs(PIReq.spellSet) do n = n + 1 end
    tickerInterval = (n * #PIReq.ActiveUnits() > SLOW_ABOVE) and INTERVAL_SLOW or INTERVAL
    ticker = C_Timer.NewTicker(tickerInterval, function()
        local ok, err = pcall(Tick)
        if not ok and PIReq.debugMode then PIReq.Print("erreur sondage : " .. tostring(err)) end
    end)
end

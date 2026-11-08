-- PIRequest — Data.lua
-- Liste des CDs offensifs (et potions) proposés dans les options.
--
-- id       : spellId de l'AURA (le buff qui apparaît sur le joueur)
-- alts     : autres spellIds de la même aura (talent, version spé…)
-- default  : false = décoché par défaut (CD mineur / court)
--
-- ⚠️ Liste à valider en jeu (patch 12.1.x) : un ID inexistant ne casse rien
-- (il ne matche jamais). Tout ID manquant peut être ajouté depuis les
-- options ("ID personnalisé") ou via /pirequest add <spellId>.

PIReq = PIReq or {}

-- Ordre d'affichage dans les options.
PIReq.CLASS_ORDER = {
    "DEATHKNIGHT", "DEMONHUNTER", "DRUID", "EVOKER", "HUNTER", "MAGE", "MONK",
    "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR", "POTION",
}

PIReq.SPELLS = {
    -- Death Knight
    { id = 51271,   class = "DEATHKNIGHT" },                 -- Pillar of Frost
    { id = 47568,   class = "DEATHKNIGHT" },                 -- Empower Rune Weapon
    { id = 207289,  class = "DEATHKNIGHT" },                 -- Unholy Assault
    -- Demon Hunter
    { id = 162264,  class = "DEMONHUNTER", alts = { 191427 } }, -- Metamorphosis (Havoc)
    -- Druid
    { id = 106951,  class = "DRUID", alts = { 102543 } },    -- Berserk / Incarnation (Feral)
    { id = 194223,  class = "DRUID", alts = { 102560 } },    -- Celestial Alignment / Incarnation (Balance)
    { id = 5217,    class = "DRUID", default = false },      -- Tiger's Fury
    -- Evoker
    { id = 375087,  class = "EVOKER" },                      -- Dragonrage
    -- Hunter
    { id = 288613,  class = "HUNTER" },                      -- Trueshot
    { id = 19574,   class = "HUNTER" },                      -- Bestial Wrath
    { id = 359844,  class = "HUNTER" },                      -- Call of the Wild
    { id = 266779,  class = "HUNTER" },                      -- Coordinated Assault
    -- Mage
    { id = 190319,  class = "MAGE" },                        -- Combustion
    { id = 365362,  class = "MAGE", alts = { 365350 } },     -- Arcane Surge
    { id = 12472,   class = "MAGE" },                        -- Icy Veins
    -- Monk
    { id = 137639,  class = "MONK" },                        -- Storm, Earth, and Fire
    { id = 152173,  class = "MONK" },                        -- Serenity
    -- Paladin
    { id = 31884,   class = "PALADIN", alts = { 231895 } },  -- Avenging Wrath / Crusade
    -- Priest
    { id = 194249,  class = "PRIEST" },                      -- Voidform
    { id = 391109,  class = "PRIEST" },                      -- Dark Ascension
    -- Rogue
    { id = 13750,   class = "ROGUE" },                       -- Adrenaline Rush
    { id = 121471,  class = "ROGUE" },                       -- Shadow Blades
    { id = 185313,  class = "ROGUE", default = false },      -- Shadow Dance
    -- Shaman
    { id = 114050,  class = "SHAMAN", alts = { 114051 } },   -- Ascendance (Elem / Enh)
    { id = 466772,  class = "SHAMAN" },                      -- Doom Winds
    -- Warlock
    { id = 113858,  class = "WARLOCK" },                     -- Dark Soul: Instability
    { id = 113860,  class = "WARLOCK" },                     -- Dark Soul: Misery
    { id = 265273,  class = "WARLOCK" },                     -- Demonic Power (Demonic Tyrant)
    -- Warrior
    { id = 1719,    class = "WARRIOR" },                     -- Recklessness
    { id = 107574,  class = "WARRIOR" },                     -- Avatar
    { id = 227847,  class = "WARRIOR", default = false },    -- Bladestorm

    -- Potions de burst Midnight (IDs résolus via wago.tools : ItemXItemEffect → ItemEffect.SpellID)
    { id = 1236616, class = "POTION" },                      -- Light's Potential (item 241308)
    { id = 1236994, class = "POTION" },                      -- Potion of Recklessness (item 241288)
    { id = 1236998, class = "POTION" },                      -- Draught of Rampant Abandon (item 241292)
    { id = 1238443, class = "POTION" },                      -- Potion of Zealotry (item 241296)
}

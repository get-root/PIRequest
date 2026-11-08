-- PIRequest — Data.lua
-- Liste des CDs offensifs (et potions) proposés dans les options.
--
-- Construite à partir de la base du jeu (export wago.tools 2026-11-08, tables
-- SpellName / SpellCooldowns / Spell) : seuls sont retenus des buffs OFFENSIFS
-- appliqués au joueur dont la description a été vérifiée. Les noms et recharges
-- en commentaire viennent de cette base.
--
-- id       : spellId de l'AURA (le buff qui apparaît sur le joueur)
-- alts     : autres spellIds de la même aura (talent, variante de spé…)
-- priority : true = recharge >= 2 min dans la base (★ en tête de liste ; seuls
--            actifs avec « prioritaires uniquement »). Recharge = la plus longue
--            entre `id` et `alts` ; "?" = non trouvée → pas de ★ (à ajuster).
-- default  : false = décoché par défaut (CD mineur / court / niche)
--
-- ⚠️ Les recharges sont celles du sort de base, hors talents. Un ID manquant
-- peut être ajouté depuis les options ou via /pirequest add <spellId>.

PIReq = PIReq or {}

-- Ordre d'affichage dans les options.
PIReq.CLASS_ORDER = {
    "DEATHKNIGHT", "DEMONHUNTER", "DRUID", "EVOKER", "HUNTER", "MAGE", "MONK",
    "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR", "POTION",
}

PIReq.SPELLS = {
    -- Deathknight
    { id = 51271, class = "DEATHKNIGHT" },  -- Pillar of Frost (cd 45s)
    { id = 207289, class = "DEATHKNIGHT" },  -- Unholy Assault (cd 1.5 min)
    { id = 1249658, priority = true, class = "DEATHKNIGHT", alts = { 152279 } },  -- Breath of Sindragosa (cd 2 min)
    -- Demonhunter
    { id = 162264, priority = true, class = "DEMONHUNTER", alts = { 191427 } },  -- Metamorphosis (cd 2 min)
    -- Druid
    { id = 106951, priority = true, class = "DRUID", alts = { 102543 } },  -- Berserk (cd 3 min)
    { id = 194223, class = "DRUID", alts = { 102560 } },  -- Celestial Alignment (cd ?)
    { id = 5217, class = "DRUID", default = false },  -- Tiger's Fury (cd 30s)
    -- Evoker
    { id = 375087, priority = true, class = "EVOKER" },  -- Dragonrage (cd 2 min)
    { id = 403631, priority = true, class = "EVOKER", default = false },  -- Breath of Eons (cd 2 min)
    -- Hunter
    { id = 288613, priority = true, class = "HUNTER" },  -- Trueshot (cd 2 min)
    { id = 19574, class = "HUNTER", alts = { 186254, 1235388, 1285912 } },  -- Bestial Wrath (cd 1.5 min)
    { id = 1250646, class = "HUNTER", alts = { 1251703 } },  -- Takedown (cd 1.5 min)
    { id = 359844, priority = true, class = "HUNTER" },  -- Call of the Wild (cd 2 min)
    { id = 266779, priority = true, class = "HUNTER" },  -- Coordinated Assault (cd 2 min)
    -- Mage
    { id = 190319, priority = true, class = "MAGE" },  -- Combustion (cd 2 min)
    { id = 365362, class = "MAGE", alts = { 365350 } },  -- Arcane Surge (cd 1.5 min)
    { id = 12472, priority = true, class = "MAGE" },  -- Icy Veins (cd 2 min)
    -- Monk
    { id = 137639, class = "MONK" },  -- Storm, Earth, and Fire (cd 16s)
    { id = 1249625, class = "MONK" },  -- Zenith (cd 16s)
    -- Paladin
    { id = 31884, priority = true, class = "PALADIN", alts = { 231895, 454351, 216331 } },  -- Avenging Wrath (cd 2 min)
    -- Priest
    { id = 194249, priority = true, class = "PRIEST" },  -- Voidform (cd 2 min)
    { id = 391109, class = "PRIEST" },  -- Dark Ascension (cd 1 min)
    -- Rogue
    { id = 13750, priority = true, class = "ROGUE" },  -- Adrenaline Rush (cd 3 min)
    { id = 121471, class = "ROGUE" },  -- Shadow Blades (cd 1.5 min)
    { id = 185422, class = "ROGUE", alts = { 185313 }, default = false },  -- Shadow Dance (cd ?)
    -- Shaman
    { id = 114050, priority = true, class = "SHAMAN", alts = { 114051, 1219480 } },  -- Ascendance (cd 3 min)
    { id = 466772, class = "SHAMAN" },  -- Doom Winds (cd ?)
    -- Warlock
    { id = 442726, class = "WARLOCK" },  -- Malevolence (cd 1 min)
    { id = 113858, priority = true, class = "WARLOCK" },  -- Dark Soul: Instability (cd 2 min)
    { id = 113860, priority = true, class = "WARLOCK" },  -- Dark Soul: Misery (cd 2 min)
    { id = 265273, class = "WARLOCK" },  -- Demonic Power (cd ?)
    -- Warrior
    { id = 1719, class = "WARRIOR" },  -- Recklessness (cd 1.5 min)
    { id = 107574, class = "WARRIOR" },  -- Avatar (cd 1.5 min)
    { id = 227847, class = "WARRIOR", default = false },  -- Bladestorm (cd 1.5 min)

    -- Potions de burst Midnight (item → ItemXItemEffect → ItemEffect.SpellID)
    { id = 1236616, class = "POTION" },  -- Light's Potential
    { id = 1236994, class = "POTION" },  -- Potion of Recklessness
    { id = 1236998, class = "POTION" },  -- Draught of Rampant Abandon
    { id = 1238443, class = "POTION" },  -- Potion of Zealotry
}

-- Sons proposés. `kit` = SoundKit (PlaySound, chemin lisible) ; `file` =
-- FileDataID (C_UnitAuras.AddAuraSound, chemin secret). Les deux désignent le
-- même son : correspondance vérifiée via les tables SoundKitEntry et le listfile
-- communautaire (chemins sound/interface/…).
PIReq.SOUNDS = {
    { key = "raidwarning", label = "Avertissement de raid",  kit = 8959,  file = 567397 }, -- raidwarning.ogg
    { key = "bosswhisper", label = "Murmure de boss",        kit = 37666, file = 876098 }, -- ui_raidbosswhisperwarning.ogg
    { key = "alarm",       label = "Réveil",                 kit = 12867, file = 567399 }, -- alarmclockwarning2.ogg
    { key = "bnettoast",   label = "Notification Battle.net",kit = 18019, file = 567402 }, -- ui_bnettoast.ogg
    { key = "levelup",     label = "Montée de niveau",       kit = 888,   file = 569593 }, -- levelup.ogg
    { key = "ping",        label = "Ping de carte",          kit = 3175,  file = 567416 }, -- mapping.ogg
    { key = "invite",      label = "Invitation",             kit = 880,   file = 567451 }, -- iplayerinvitea.ogg
    { key = "bell",        label = "Cloche",                 kit = 6674,  file = 566558 }, -- belltollnightelf.ogg
    { key = "rep",         label = "Réputation",             kit = 8473,  file = 568016 }, -- reputationlevelup.ogg
}

# PIRequest — WoW Addon Context

## Objectif
Addon World of Warcraft permettant à un prêtre heal (Holy/Discipline) de savoir
automatiquement quand un coéquipier DPS active un gros CD offensif — le moment
idéal pour caster **Power Infusion (Infusion de Puissance)**.

Contexte : depuis Midnight, Blizzard a introduit des "valeurs secrètes" qui cassent
les addons de tracking de cooldowns comme OmniCD. Cet addon contourne le problème
en observant passivement les auras des coéquipiers via `UNIT_AURA`, sans aucune
communication inter-joueurs.

---

## Approche technique : détection passive via UNIT_AURA

Blizzard classe nativement les gros CDs offensifs (Combustion, Témérité, Dragonrage,
Avatar…) avec le filtre interne `HELPFUL|IMPORTANT`.

L'addon écoute `UNIT_AURA` pour chaque membre du groupe. Pour chaque aura ajoutée,
il vérifie via `C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, instanceID, "HELPFUL|IMPORTANT")` :
- si cette fonction retourne `false` → l'aura correspond au filtre → alerte déclenchée.
- si cette fonction retourne une **secret value** (cas cross-realm sur Midnight) → traité comme un match.

Validation secondaire via `C_Spell.IsSpellImportant(spellId)` si le `spellId` est disponible.

⚠️ `aura.classification` n'est **pas** un champ de `AuraData` — c'est un filtre de
requête. La détection passe par `IsAuraFilteredOutByInstanceID`, pas par un champ direct.

**Avantages :**
- Fonctionne en M+ (UNIT_AURA non bloqué)
- Cross-realm (pas de communication réseau)
- Pas de liste de spell IDs à maintenir
- Aucune action requise côté DPS

---

## Spécifications fonctionnelles

### Rôles
- **Prêtre** : Holy ou Discipline. Observe les auras, affiche le highlight.
- **DPS** : Ne fait rien de spécial — l'addon détecte ses CDs automatiquement.
- Les deux joueurs doivent avoir l'addon installé.

### Règles métier
- Seuls les prêtres healers (Holy/Disc) activent la détection.
- Déduplication : une alerte pour le même joueur est ignorée pendant 10 secondes.
- La liste des units surveillés est mise à jour à chaque `GROUP_ROSTER_UPDATE`.
- Les alertes peuvent être désactivées à la volée via `/pirequest disable` sans /reload.

---

## Structure des fichiers

```
PIRequest/
├── CLAUDE.md           ← ce fichier
├── PIRequest.toc       ← déclaration de l'addon
├── Core.lua            ← init, détection du rôle (prêtre vs DPS), slash commands
├── AuraWatcher.lua     ← UNIT_AURA watcher, déclenchement des alertes
└── Highlighter.lua     ← highlight barre de vie + notification aura
```

---

## Détails techniques

### Détection du rôle
```lua
local function IsPriestHealer()
    local _, class = UnitClass("player")
    if class ~= "PRIEST" then return false end
    local spec = GetSpecialization()
    return spec == 1 or spec == 2  -- 1 = Discipline, 2 = Holy
end
```

### Détection des auras IMPORTANT
```lua
-- Pour chaque aura ajoutée dans updateInfo.addedAuras :
local filtered = C_UnitAuras.IsAuraFilteredOutByInstanceID(
    unit, aura.auraInstanceID, "HELPFUL|IMPORTANT"
)
-- filtered == false  → match direct
-- issecretvalue(filtered) → match cross-realm (Midnight)
if filtered == false or issecretvalue(filtered) then
    PIReq_Highlight(playerName)
end

-- Fallback : validation via C_Spell.IsSpellImportant
if aura.spellId and C_Spell and C_Spell.IsSpellImportant then
    local imp = C_Spell.IsSpellImportant(aura.spellId)
    if imp == true or issecretvalue(imp) then PIReq_Highlight(playerName) end
end

-- Si isFullUpdate == true (pas d'addedAuras) : scan via GetAuraDataByIndex.
-- N'alerte que si l'unité passe d'un état sans aura IMPORTANT à avec
-- (évite les faux positifs sur zone-in / reload).
```

### Highlight (Highlighter.lua)
- Bordure animée dorée sur le frame de raid du DPS
- Pulse alpha 0.4 → 1.0, durée 15s, ticker 100ms
- Notification : icône PI + nom du joueur, durée 5s, draggable
- Frame de notification créé à `PLAYER_ENTERING_WORLD` (CreateFrame interdit en combat)

### Numéro d'interface TOC
Récupérer en jeu avec : `/run print(GetBuildInfo())`

---

## Commandes slash
```
/pirequest test      → déclenche une notification test avec son propre nom
/pirequest scan      → liste les membres du groupe et leurs auras IMPORTANT actives
/pirequest status    → affiche isPriest + spec courante + état enabled
/pirequest debug     → toggle mode debug (affiche les auras détectées en temps réel)
/pirequest toggle    → active/désactive les alertes à la volée
/pirequest enable    → active les alertes
/pirequest disable   → désactive les alertes
```

---

## ⚠️ Approches abandonnées

Toutes les approches par envoi de messages inter-joueurs ont été abandonnées car
**Blizzard bloque ou tainte tous les canaux en M+ Midnight** :
- `CHAT_MSG_ADDON` : event bloqué pendant la clé
- `SendChatMessage` (YELL, WHISPER, CHANNEL) : bloqué ou message/sender tainté
- Canaux custom : cross-realm impossible

La solution UNIT_AURA est la seule approche passive qui fonctionne en M+.

---

## Notes de compatibilité

### Patch 12.0.5+
`UNIT_SPELLCAST_SUCCEEDED` ne fire plus pour les autres joueurs depuis 12.0.5.
PIRequest n'est **pas affecté** car il repose uniquement sur `UNIT_AURA`.

### Secret values (Midnight)
`IsAuraFilteredOutByInstanceID` peut retourner une valeur opaque (secret value) pour
les joueurs cross-realm. L'addon traite ces valeurs comme des matches valides via
`issecretvalue()` plutôt que de les ignorer silencieusement.

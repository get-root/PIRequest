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
Avatar…) avec `classification = "important"` dans les données d'aura.

L'addon écoute `UNIT_AURA` pour chaque membre du groupe. Quand une aura
`isHelpful == true` et `classification == "important"` apparaît sur un coéquipier,
il déclenche le highlight + notification côté prêtre.

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
-- Dans le handler UNIT_AURA, pour chaque aura ajoutée :
if aura.isHelpful and aura.classification == "important" then
    PIReq_Highlight(playerName)
end
```

### Highlight (Highlighter.lua)
- Bordure animée dorée sur le frame de raid du DPS
- Pulse alpha 0.4 → 1.0, durée 15s
- Notification : icône PI + nom du joueur, durée 5s, draggable

### Numéro d'interface TOC
Récupérer en jeu avec : `/run print(GetBuildInfo())`

---

## Commandes slash
```
/pirequest test      → déclenche une notification test avec son propre nom
/pirequest status    → affiche isPriest + spec courante
/pirequest debug     → toggle mode debug (affiche les auras détectées)
```

---

## ⚠️ Approches abandonnées

Toutes les approches par envoi de messages inter-joueurs ont été abandonnées car
**Blizzard bloque ou tainte tous les canaux en M+ Midnight** :
- `CHAT_MSG_ADDON` : event bloqué pendant la clé
- `SendChatMessage` (YELL, WHISPER, CHANNEL) : bloqué ou message/sender tainté
- Canaux custom : cross-realm impossible

La solution UNIT_AURA est la seule approche passive qui fonctionne en M+.

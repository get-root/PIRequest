# PIRequest — WoW Addon Context

## Objectif
Addon World of Warcraft permettant à un prêtre heal (Holy/Discipline) de savoir
automatiquement quand un coéquipier DPS active un gros CD offensif ou une potion
de burst — le moment idéal pour caster **Power Infusion (Infusion de Puissance)**.
Les CDs **défensifs** ne déclenchent pas d'alerte.

Contexte : depuis Midnight (12.0), les "secret values" cachent le contenu des
auras des autres joueurs en combat / M+ / boss / PvP. Cet addon contourne le
problème en n'exploitant que les requêtes filtrées côté serveur, sans jamais
lire le contenu des auras et sans aucune communication inter-joueurs.

---

## Approche technique : ensembles d'auraInstanceID via filtres serveur

En 12.0.5, le contenu des auras (spellId, nom…) des autres joueurs est secret
dès que : une clé M+ est lancée, un combat de boss est en cours, un match PvP
est actif, ou le joueur est en combat. **Mais** les requêtes filtrées
`C_UnitAuras.GetUnitAuras(unit, filtre)` sont évaluées côté serveur et
retournent une liste exploitable : le nombre d'éléments et les
`auraInstanceID` ne sont pas secrets.

Filtres utilisés (12.0.1+, mêmes que MiniCC) :
- `HELPFUL|IMPORTANT` — auras passant `C_Spell.IsSpellImportant()` (gros CDs, offensifs ET défensifs)
- `HELPFUL|BIG_DEFENSIVE` — gros défensifs personnels
- `HELPFUL|EXTERNAL_DEFENSIVE` — défensifs externes (Pain Suppression, etc.)

**Détection offensive = IMPORTANT − (BIG_DEFENSIVE ∪ EXTERNAL_DEFENSIVE)**,
par soustraction d'ensembles d'`auraInstanceID`. À chaque `UNIT_AURA`, on
reconstruit l'ensemble offensif du unit et on alerte si un nouvel ID apparaît.

MiniCC (3.25.0) utilise exactement ces filtres avec un set `seen` pour
dédupliquer défensifs/importants ; nous inversons la logique pour ne garder
que l'offensif.

### Potions de burst
Détectées via `updateInfo.addedAuras` quand le `spellId` est lisible (hors
conditions secrètes — couvre le pre-pot avant le pull). IDs Midnight résolus
via wago.tools (`ItemXItemEffect` → `ItemEffect.SpellID`) :
- 1236616 Light's Potential (item 241308)
- 1236994 Potion of Recklessness (item 241288)
- 1236998 Draught of Rampant Abandon (item 241292)
- 1238443 Potion of Zealotry (item 241296)

En combat, le spellId est secret : la potion n'est alors détectée que si
Blizzard la classe IMPORTANT (vérifiable in-game avec `/pirequest scan`).

### Pièges connus (NE PAS revenir en arrière)
- ⚠️ `C_UnitAuras.IsAuraFilteredOutByInstanceID` retourne des **secret values
  en combat pour tout le monde** (pas seulement cross-realm). Traiter
  `issecretvalue() == match` ⇒ faux positifs massifs (n'importe quel buff
  alerte). C'est le bug qui a motivé la réécriture v2.
- ⚠️ `aura.classification` n'est pas un champ d'`AuraData`.
- ⚠️ Les `auraInstanceID` sont **re-randomisés** à l'entrée en M+ / boss /
  PvP : l'addon rebase ses ensembles sans alerter pendant 3 s sur
  `PLAYER_ENTERING_WORLD`, `ENCOUNTER_START`, `CHALLENGE_MODE_START`,
  `PVP_MATCH_ACTIVE`.
- ⚠️ `UNIT_SPELLCAST_SUCCEEDED` ne fournit plus de spellId exploitable pour
  les autres joueurs en 12.0.5 (secret) ; il ne fire de façon fiable que pour
  `"player"`. Inutilisable pour détecter les CDs des coéquipiers.
- Garde anti-données corrompues (unités hors de portée, cf. MiniCC) : quand le
  spellId est lisible, revalider avec `C_Spell.IsSpellImportant` /
  `C_UnitAuras.AuraIsBigDefensive` — n'écarter que sur un `false` certain,
  jamais sur une secret value.

**Avantages :**
- Fonctionne en M+ et en combat (filtres serveur non bloqués)
- Cross-realm (pas de communication réseau)
- Pas de liste de spell IDs de classes à maintenir (seulement les potions)
- Aucune action requise côté DPS

---

## Spécifications fonctionnelles

### Rôles
- **Prêtre** : Holy ou Discipline. Observe les auras, affiche le highlight + son.
- **DPS** : Ne fait rien de spécial — l'addon détecte ses CDs automatiquement.
- Seul le prêtre a besoin de l'addon.

### Règles métier
- Seuls les prêtres healers (Holy/Disc) activent la détection.
- Alerte uniquement pour les DPS : `UnitGroupRolesAssigned` ≠ TANK/HEALER
  (rôle inconnu = alerte quand même).
- Déduplication : une alerte pour le même joueur est ignorée pendant 10 s.
- Pas d'alerte pendant 3 s après un rebase (re-randomisation des IDs).
- La liste des units surveillés est reconstruite à chaque `GROUP_ROSTER_UPDATE`.
- Les alertes peuvent être désactivées à la volée via `/pirequest disable`.

---

## Structure des fichiers

```
PIRequest/
├── CLAUDE.md           ← ce fichier
├── PIRequest.toc       ← déclaration de l'addon (Interface 120005)
├── Core.lua            ← init, détection du rôle, slash commands
├── AuraWatcher.lua     ← ensembles offensifs par unit, alertes, potions
└── Highlighter.lua     ← highlight barre de vie + notification + son
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

### Cœur de la détection (AuraWatcher.lua)
```lua
-- À chaque UNIT_AURA sur un unit surveillé :
local defensive = {}  -- auraInstanceID matchant un filtre défensif
for _, filter in ipairs({ "HELPFUL|BIG_DEFENSIVE", "HELPFUL|EXTERNAL_DEFENSIVE" }) do
    for _, aura in ipairs(C_UnitAuras.GetUnitAuras(unit, filter)) do
        defensive[aura.auraInstanceID] = true
    end
end
local set = {}
for _, aura in ipairs(C_UnitAuras.GetUnitAuras(unit, "HELPFUL|IMPORTANT")) do
    if not defensive[aura.auraInstanceID] then set[aura.auraInstanceID] = true end
end
-- comparer à l'ensemble précédent : nouvel ID ⇒ TryAlert(unit)
```

### Highlight (Highlighter.lua)
- Bordure animée dorée sur le frame de raid du DPS
- Pulse alpha 0.4 → 1.0, durée 15s, ticker 100ms
- Notification : icône PI + nom du joueur, durée 5s, draggable
- Son `SOUNDKIT.RAID_WARNING` (désactivable via `/pirequest sound`)
- Frame de notification créé à `PLAYER_ENTERING_WORLD` (CreateFrame interdit en combat)

### Numéro d'interface TOC
Récupérer en jeu avec : `/run print(GetBuildInfo())`

---

## Commandes slash
```
/pirequest test      → déclenche une notification test avec son propre nom
/pirequest scan      → compte par membre : important / bigDef / extDef / offensif
/pirequest status    → affiche isPriest + spec courante + état enabled
/pirequest debug     → toggle mode debug (trace les détections en temps réel)
/pirequest sound     → toggle le son d'alerte
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

L'approche v1 (`IsAuraFilteredOutByInstanceID` par aura ajoutée + secret value
= match) a été abandonnée : faux positifs massifs en combat (voir Pièges).

La soustraction d'ensembles via filtres serveur est la seule approche passive
fiable en M+.

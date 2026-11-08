# PIRequest — WoW Addon Context

## Objectif
Addon World of Warcraft permettant à un prêtre heal (Holy/Discipline) de savoir
automatiquement quand un coéquipier DPS active un gros CD offensif ou une potion
de burst — le moment idéal pour caster **Power Infusion (Infusion de Puissance)**.
Les CDs **défensifs** ne déclenchent pas d'alerte.

Contexte : depuis Midnight (12.0), les "secret values" cachent le contenu des
auras des autres joueurs en combat / M+ / boss / PvP. Cet addon contourne le
problème en ne lisant le contenu des auras que quand il est lisible, et en
déléguant la comparaison au moteur (sons + AuraContainer filtrés par spellId)
quand il est secret — sans aucune communication inter-joueurs.

---

## Approche technique (12.1.5, Interface 120105)

⚠️ **12.1 a cassé l'approche v2** (ensembles d'`auraInstanceID` via
`GetUnitAuras(IMPORTANT/BIG_DEFENSIVE/…)`) : quand les auras sont secrètes
(combat, boss, M+, PvP) toutes les API UnitAura renvoient secret/nil ou lèvent
une erreur, y compris par index/slot/instanceID ; `UNIT_AURA` a un payload
entièrement secret et `AuraData` est toujours secret. Sources : warcraft.wiki.gg
`Patch_12.1.0/API_changes/notes`, `Patch_12.1.5/API_changes`.

L'état se teste avec `C_Secrets.ShouldAurasBeSecret()` (`PIReq.IsRestricted()`),
dynamique : vrai en combat même en monde ouvert, vrai pendant toute une clé M+.
Deux chemins :

1. **Lisible** (`AuraWatcher.lua`) — `UNIT_AURA.addedAuras[].spellId` comparé à
   la liste choisie. Bannière + highlight raid frame + son.
2. **Secret** (`Engine.lua`) — le moteur compare à notre place :
   - `C_UnitAuras.AddAuraSound(trigger, {unitToken, spellID, soundFileID,
     outputChannel, throttleSeconds≤5})` → son à l'ajout de l'aura ;
   - `AuraContainer` (`CustomAuraContainerTemplate`, `AddAuraGroup` avec
     `candidateFilters.includeSpellIDs`, `SetUnit`) → icône + nom du joueur.
   Aucun callback Lua : pas de bannière en mode secret. Les boutons d'aura sont
   *forbidden* quand les auras sont secrètes (on ne peut pas hooker Show/Hide).
   Tout se configure dans `initializeFrame` (fenêtre de création légale).

Technique inspirée d'EllesmereUI (AuraKit + RaidFrames) — licence « tous droits
réservés » : **ne rien copier** (ni code ni listes).

### Filtres utilisateur (SavedVariables `PIRequestDB`)
- `filterByName` + `names` : optionnel, limite à certains personnages (le rôle
  est alors ignoré). Les sons moteur sont enregistrés par unité → seules les
  unités filtrées sont enregistrées.
- `spells[id]` (surcharge du défaut de `Data.lua`) + `custom[id]`.
- Tout changement ⇒ `PIReq.ApplyConfig()` (reconstruit le set + `Refresh`).

### Pièges connus
- `UnitName`/`GetUnitName` peuvent être secrets : `PIReq.UnitShortName` garde un cache.
- `UNIT_SPELLCAST_SUCCEEDED` inutilisable pour les autres joueurs.
- `AddAuraSound` / création de containers : appels potentiellement refusés en
  combat → `pendingSync` retenté à `PLAYER_REGEN_ENABLED`.
- Ne jamais comparer/itérer une valeur sans `issecretvalue()` d'abord.
- ⚠️ Code **non testé en jeu** (écrit sans client) : à valider avec
  `/pirequest scan` et `/pirequest debug` — notamment sons parasites à l'entrée
  d'une instance (aura « Added » initiale) et rendu des icônes.

---

## Spécifications fonctionnelles

- Seuls les prêtres Holy/Disc activent la détection.
- Par défaut alerte pour les DPS (rôle ≠ TANK/HEALER, inconnu = alerte).
- Dédup 10 s par joueur (chemin lisible) ; le son moteur est throttlé 5 s.
- Le filtre par nom est optionnel ; la liste de CDs est modifiable (options).
- Roster reconstruit à `GROUP_ROSTER_UPDATE` / `PLAYER_ROLES_ASSIGNED`.

---

## Structure des fichiers

```
PIRequest.toc    ← Interface 120105, SavedVariables PIRequestDB
Data.lua         ← liste des CDs offensifs + potions (par classe)
Core.lua         ← DB, IsRestricted, filtres nom/rôle, slash commands
Highlighter.lua  ← bannière + highlight raid frame + son (chemin lisible)
AuraWatcher.lua  ← chemin lisible (UNIT_AURA)
Engine.lua       ← chemin secret (AddAuraSound + AuraContainer + tracker)
Options.lua      ← panneau d'options (Settings canvas)
```

## Commandes slash
`config | only <noms>|off | add/remove <id> | tracker | test | status | scan | sound | toggle | enable | disable | debug`

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

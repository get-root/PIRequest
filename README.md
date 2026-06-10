# PIRequest — WoW Addon

World of Warcraft addon for Holy/Discipline priests that automatically detects when a DPS teammate activates a major offensive cooldown or a burst potion — the ideal moment to cast **Power Infusion**. Defensive cooldowns are deliberately ignored.

> **Context:** Since Midnight (12.0), "secret values" hide the contents of other players' auras during combat, M+, boss encounters and PvP. PIRequest works around this by relying exclusively on server-side filtered aura queries — it never needs to read aura contents, and requires no inter-player communication.

---

## How it works

1. The **Priest** installs the addon — no configuration needed. The DPS needs nothing.
2. The addon detects the priest's spec (Holy or Disc) and watches group members.
3. When a DPS gains an offensive **IMPORTANT** aura (Combustion, Recklessness, Dragonrage, Avatar…) or a Midnight burst potion, a golden pulsing border appears on their raid frame for 15 seconds, a notification (PI icon + player name) pops up for 5 seconds, and a raid-warning sound plays.

Detection is fully passive and works cross-realm.

---

## Installation

1. Download the latest release zip.
2. Extract into `World of Warcraft/_retail_/Interface/AddOns/PIRequest/`.
3. Reload the UI (`/reload`).

---

## Commands

```
/pirequest test      — trigger a test notification with your own name
/pirequest scan      — per member: important / bigDef / extDef / offensive aura counts
/pirequest status    — show isPriest, current spec, and enabled state
/pirequest sound     — toggle the alert sound
/pirequest toggle    — enable/disable alerts on the fly (no /reload needed)
/pirequest enable    — enable alerts
/pirequest disable   — disable alerts
/pirequest debug     — toggle debug mode (prints detections in real time)
```

---

## Compatibility

- **WoW Version:** Midnight 12.0.5 (Interface 120005)
- **Group types:** Mythic+ and Raid
- **Cross-realm:** works — no network communication, purely local aura detection
- Does not rely on `UNIT_SPELLCAST_SUCCEEDED` (unusable for other players since 12.0.5)

---

## Technical approach

The contents of other players' auras are secret in combat, but server-side filtered queries via `C_UnitAuras.GetUnitAuras(unit, filter)` still return usable lists (`auraInstanceID`s are not secret). PIRequest computes, per unit:

```
offensive = HELPFUL|IMPORTANT − (HELPFUL|BIG_DEFENSIVE ∪ HELPFUL|EXTERNAL_DEFENSIVE)
```

as a set of `auraInstanceID`s. A new ID appearing in the offensive set triggers the alert. This is the same filter machinery MiniCC uses — inverted to keep only offensive cooldowns. No class spell ID list to maintain.

Burst potions (Light's Potential, Potion of Recklessness, Draught of Rampant Abandon, Potion of Zealotry) are additionally detected from `addedAuras` whenever the aura `spellId` is readable — which covers pre-pull potions.

Aura instance IDs are re-randomized when entering M+/encounters/PvP; the addon re-baselines its sets without alerting for 3 seconds on those events.

---

## License

MIT

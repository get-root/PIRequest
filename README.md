# PIRequest — WoW Addon

World of Warcraft addon for Holy/Discipline priests that automatically detects when a DPS teammate activates a major offensive cooldown — the ideal moment to cast **Power Infusion**.

> **Context:** Since Midnight, Blizzard introduced "secret values" that break cooldown tracking addons like OmniCD. PIRequest works around this by passively observing teammate auras via `UNIT_AURA`, with no inter-player communication required.

---

## How it works

1. The **Priest** installs the addon — no configuration needed.
2. The addon automatically detects the priest's spec (Holy or Disc) and starts watching group members.
3. When a DPS activates a major offensive cooldown (Combustion, Recklessness, Dragonrage, Avatar…), a golden pulsing border appears on their raid frame for 15 seconds, and a 5-second notification aura (PI icon + player name) pops up.

Neither the priest nor the DPS needs to do anything — detection is fully passive.

---

## Installation

1. Download the latest release zip.
2. Extract into `World of Warcraft/_retail_/Interface/AddOns/PIRequest/`.
3. Reload the UI (`/reload`).

---

## Commands

```
/pirequest test      — trigger a test notification with your own name
/pirequest scan      — list group members and their active IMPORTANT auras
/pirequest status    — show isPriest, current spec, and enabled state
/pirequest toggle    — enable/disable alerts on the fly (no /reload needed)
/pirequest enable    — enable alerts
/pirequest disable   — disable alerts
/pirequest debug     — toggle debug mode (prints detected auras in real time)
```

---

## Compatibility

- **WoW Version:** Midnight (Interface 120001)
- **Group types:** Mythic+ and Raid
- **Cross-realm:** works — no network communication, purely local aura detection
- **Patch 12.0.5+:** compatible — does not rely on `UNIT_SPELLCAST_SUCCEEDED`

---

## Technical approach

Detection uses `C_UnitAuras.IsAuraFilteredOutByInstanceID` with the `HELPFUL|IMPORTANT` filter — the same filter Blizzard uses internally to classify major offensive cooldowns. No spell ID list to maintain.

For cross-realm players on Midnight, Blizzard returns opaque "secret values" instead of `true`/`false`. PIRequest handles this via `issecretvalue()` so cross-realm DPS cooldowns are never silently missed. A secondary validation via `C_Spell.IsSpellImportant` provides an additional fallback.

---

## License

MIT

# PIRequest — WoW Addon

World of Warcraft addon allowing a DPS to signal a healer Priest that they want a **Power Infusion**.

> **Context:** Since Midnight, Blizzard introduced "secret values" that break cooldown tracking addons like OmniCD. This addon works around the problem via an explicit communication system between players.

---

## How it works

- The **Priest** broadcasts their presence (`HELLO:HOLY` or `HELLO:DISC`) to the group on login and roster changes.
- The **DPS** clicks a macro that whispers a `REQUEST` to the detected priest.
- The **Priest** sees a pulsing golden border on the DPS's raid frame for 15 seconds.

Both players must have the addon installed.

---

## Installation

1. Download the latest release zip.
2. Extract into `World of Warcraft/_retail_/Interface/AddOns/PIRequest/`.
3. Reload the UI (`/reload`).

---

## Usage

### DPS Macro

```
/run PIReq_SendRequest()
/cast [Your DPS Spell]
```

### Debug Commands

```
/run PIReq_SendRequest()               -- test sending a request
/run print(PIReq.knownPriests)         -- show known priests registry
/run print(GetSpellCooldown(10060))    -- check PI cooldown
```

---

## Compatibility

- **WoW Version:** 12.0.1 (Interface 120001)
- **Group types:** Mythic+ and Raid
- **Multiple priests:** Each DPS whispers the correct priest directly

---

## Roadmap

- **V1 (current):** Dynamic priest discovery, request sending, raid frame highlight, deduplication
- **V2 (planned):** `ACK` reply if PI available, `COOLDOWN:XX` reply if on cooldown

---

## License

MIT

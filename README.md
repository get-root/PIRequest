# PIRequest — WoW Addon

World of Warcraft addon for Holy/Discipline priests that alerts you when a DPS teammate activates a major offensive cooldown or a burst potion — the ideal moment to cast **Power Infusion**.

- **Optional filter by character name** — only be alerted for the player(s) you actually PI.
- **You choose which cooldowns trigger the alert** (per class, plus custom spell IDs).
- Nothing required from the DPS, no inter-player communication, cross-realm.

> **Context (12.1):** while auras are *secret* (combat, boss, M+, PvP) addons can no longer read other players' auras. PIRequest therefore has two detection paths, switched automatically with `C_Secrets.ShouldAurasBeSecret()`.

---

## How it works

| Situation | Path | What you get |
|---|---|---|
| Auras readable (open world, out of combat, pre-pot…) | `UNIT_AURA` → `spellId` compared to your list | Banner (spell + player), pulsing border on the raid frame, sound |
| Auras secret (combat, boss, M+, PvP) | Engine-side: `C_UnitAuras.AddAuraSound` + `AuraContainer` filtered by `includeSpellIDs` | Sound + movable icon with the player's name while the CD is up |

In secret contexts the engine does the comparison for us; Lua gets no callback, hence no banner/raid-frame highlight there.

---

## Installation

Extract into `World of Warcraft/_retail_/Interface/AddOns/PIRequest/` then `/reload`.
Options: `Esc > Options > AddOns > PIRequest` or `/pirequest config`.

## Commands

```
/pirequest config            — open the options panel
/pirequest only Name1 Name2  — only alert for these characters  (/pirequest only off to disable)
/pirequest add <spellId>     — add a custom aura spell ID   (/pirequest remove <spellId>)
/pirequest tracker           — unlock/lock the movable icon tracker
/pirequest test              — trigger a test banner
/pirequest status            — state, secret-aura status, name filter
/pirequest scan              — watched units, active spell IDs, engine sounds/icons
/pirequest sound | toggle | enable | disable | debug
/pirequest auras [unit]      — list readable buffs + spell IDs (out of combat) to find a CD's real aura ID
/pirequest secrecy | resync | ctest [unit] [filtre]   — engine diagnostics
```

## Compatibility

- **WoW 12.1.5** (Interface 120105). Not usable on pre-12.1 clients.
- The built-in spell list must be validated in-game; fix or extend it via the options panel.

## Credits

The AuraContainer-by-spellId technique was learned from reading how EllesmereUI renders auras. No code or data is copied from it.

## License

MIT

## Sound & Power Infusion cooldown

- **Sound picker** (options → *Tous les sons…*): recommended sounds, sounds shared by other addons through LibSharedMedia (BigWigs, WeakAuras, SharedMedia…), and ~1200 game sounds grouped by category. A raw FileDataID can still be typed in.
- **Muted while Power Infusion is on cooldown** (optional): alerts are re-armed a few seconds before PI is ready (10 s by default, configurable), so a DPS re-using a 2-minute cooldown right on time is not missed.
- In raid, engine sounds are registered per player for their own class's cooldowns only (plus potions and custom IDs).

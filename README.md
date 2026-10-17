# EllesmereUI Food Timer
<img width="1770" height="1018" alt="image" src="https://github.com/user-attachments/assets/5c9a9895-afc0-442c-aa8b-4fd469b48b3d" />

An eating, drinking and Well Fed timer, built as a module for the **Dworak** section of [EllesmereUI](https://www.curseforge.com/wow/addons/ellesmereui).
It shows how long you still sit and eat or drink, tells you when your health or mana is full, and keeps an eye on your Well Fed buff.

Made for **WoW Forever** (Interface 16001) with **EllesmereUI 9.5.4**. The `.toc` also lists the 12.0.x / 12.1 interface numbers.

```
[icon] Food           HP 72%   18.4s    ← drains with the buff
[icon] Drink            Full   22.0s    ← Full color: you can stand up

        ┌──────┐
        │ 10:23│                         ← Well Fed icon, moved on its own
        └──────┘
```

Every food and drink is found by the **buff's name** (*Food*, *Drink*, *Food & Drink*, *Refreshment*, *Well Fed*), not by spell ID. Each food has its own spell ID, but the buff's name is always the same. The names are read from the client, so non-English clients work too.

## Features

### Food & Drink bars
- **One bar per buff** while you eat or drink: the buff's icon, its name, and the time left. The bar drains as the buff runs out.
- **Health / mana:** health % on the Food bar, mana % on the Drink bar.
- **Full Highlight:** when your health (food) or mana (drink) is full, the bar turns the *Full* color (green by default) and reads **Full**.
- Eating and drinking at once shows two bars. They stack downwards or upwards.
- Drink tracking can be switched off (food only).

### Well Fed icon
- A separate **icon** for the Well Fed buff from buff food, with the **time left inside** (`1h`, `10:23`, `45s`) and an optional clock-style **swipe**.
- **Moves on its own** in Unlock Mode, independently of the bars.
- **Show When Missing:** without Well Fed, the icon stays in place, greyed out, as a reminder to eat buff food.
- Works when the buff lands **in combat** too. See [How it works](#how-it-works).

### Look
- **Bars:** width, height, icon, name, font, text size, text color, background color and opacity, grow direction, decimals in the last 10 seconds.
- **Separate colors** for the Food bar and the Drink bar: the UI Accent Color or a custom color. The *Full* color has its own swatch.
- **Well Fed icon:** size, border size (0 removes it), border color (UI Accent or custom), swipe on/off, timer text size and timer color.
- Both frames are movable in EllesmereUI **Unlock Mode** (group *Dworak*): **Food Timer** for the bars, **Well Fed** for the icon.
- The UI Accent Color from Global Settings applies live.
- The settings page has a live preview of the bars and the Well Fed icon.

## Requirements

- [EllesmereUI](https://www.curseforge.com/wow/addons/ellesmereui)
- **EllesmereUIDworak**, the host addon that owns the *Dworak* section of the EllesmereUI panel

## Installation

1. Copy the `EllesmereUIFoodTimer` folder into `World of Warcraft\_classic_beta_\Interface\AddOns\`. Use your client's own folder if it's different.
2. Make sure `EllesmereUI` and `EllesmereUIDworak` are installed and enabled.
3. Log in or `/reload`. The module appears under **EllesmereUI → Dworak → Food Timer**.

## Commands

| Command | What it does |
| --- | --- |
| `/foodtimer` or `/euifood` | Opens the settings page |
| `/foodtimer debug` | Prints the buff names it looks for, your raw health and mana readings, whether the client's curve API is there, every matching buff with its raw duration, and the bars it would show |

## Settings

| Section | Options |
| --- | --- |
| Food Timer | On/off, Track Drink, Show Health / Mana, Full Highlight (with color) |
| Well Fed Icon | Track Well Fed, Border Color, Icon Size, Border Size, Show Swipe, Timer Text Size, Show When Missing, Timer Color |
| Display | Bar Width, Bar Height, Show Icon, Show Name, Food Bar Color, Drink Bar Color, Background, Grow Direction, Font, Text Size, Text Color, Decimals Under 10s |

Settings are saved per EllesmereUI profile in `EllesmereUIFoodTimerDB`.

## How it works

- **Matching by name:** the names come from `C_Spell.GetSpellName` of the basic Food (433), Drink (430) and Well Fed (19705) spells, plus the English names as a fallback. *Food & Drink* and *Refreshment* count as both.
- **Buffs:** `C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")`, on `UNIT_AURA`. While the bars are shown, it also rescans once per second. A buff that arrives before its duration is filled in is retried for a few seconds.
- **Secret values:** on WoW Forever, the player's health and mana are 12.0 *secret values*, even out of combat. Lua can't compare them. The addon therefore:
  - prints the percent with `UnitHealthPercent` / `UnitPowerPercent` (`CurveConstants.ScaleTo100`) straight into the font string;
  - decides **Full** inside the client, using curves (`C_CurveUtil`) that set the bar color and the alpha of the *Full* text. A secret value is never compared in Lua.
- **Well Fed in combat:** buff data is secret in combat, so the name match can't see a Well Fed that lands then. The addon:
  - asks the client by name (`C_UnitAuras.GetAuraDataBySpellName`);
  - drives the icon's cooldown from the aura's duration object, and lets the cooldown's own countdown show the time;
  - rescans when combat ends;
  - keeps the readable timer through combat for a Well Fed you already had before the pull.
- No EllesmereUI file is modified. The module registers through `EllesmereUIDworak.AddModule`.

## Known limitations

- **Early version.** The bars, health / mana and the Full highlight have been tested in game. The Well Fed icon and its combat handling haven't been tested yet. 
- When the Well Fed buff lands in combat, the client's own countdown shows the time, so it can look a little different (for example `10m` instead of `10:23`) until combat ends.
- If your client lacks the curve API, the bars still show the percent but can't detect *Full*.
- The Full Highlight follows health on the Food bar and mana on the Drink and *Food & Drink* bars.

## Author

Dworak

# StatBuffs

A small addon for WoW 3.3.5a (AzerothCore / ChromieCraft) that shows a movable window
listing the cumulative stat bonuses currently on your character. It updates live as
buffs are gained or lost, gear changes, or talents are swapped.

"Bonus" means everything above your naked base value. Gear, enchants, consumables and
buffs are all counted together. Only stats with a nonzero bonus are listed, so the
window stays short.

## Usage

- `/sb` or `/statbuffs` toggles the window.
- The **Chat** button on the window exports the current list to chat: your own chat
  window, Say, Party, Raid, Guild or Officer.
- `/sb export` prints the list to your own chat window. `/sb export party` (or `say`,
  `raid`, `guild`, `officer`, `bg`), `/sb export whisper <name>` and `/sb export <channel number>`
  send it to others. Long sections are split across several messages.
- `/sb scale 0.8` shrinks (or enlarges) the window; any value from 0.5 to 2 works.
- `/sb reset` recentres the window and restores the default scale.
- The window auto-sizes to its content; a scrollbar appears only when the list is long.
- A keybinding is available under **Key Bindings > StatBuffs**.
- Drag the window to move it; the position is saved.
- The window stays open until you close it with the X button or `/sb`, and it reopens
  on login or reload if it was open. Escape does not close it; it opens the game menu
  as usual.

## What it shows

| Section | Rows (only when bonus is nonzero) | Bonus column | Total column |
|---|---|---|---|
| Attributes | Strength, Agility, Stamina, Intellect, Spirit | bonus above base | current value |
| Attack | Melee / ranged attack power | bonus above base | current value |
| Attack | Crit, hit, haste, expertise, armor penetration | rating | resulting percent |
| Spell | Holy, Fire, Nature, Frost, Shadow, Arcane spell damage; bonus healing; spell penetration | value | value |
| Spell | Spell crit, hit, haste | rating | resulting percent |
| Defense | Armor, Defense | bonus above base | current value |
| Defense | Dodge, parry, block, resilience | rating | resulting percent |
| Resistances | Fire, Nature, Frost, Shadow, Arcane | bonus above base | current value |
| Active buffs | Icon, name, stack count, remaining time | | |

Note: percent-based stats that have no rating (for example a flat +5% crit aura) do
not appear as their own row, because the client does not report them separately.

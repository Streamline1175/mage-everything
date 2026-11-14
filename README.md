# Mage Everything

A personal Mage addon for **World of Warcraft: Forever** (client 1.60.1, interface 16001).

It shows the best spell to press next for the situation you are in, alerts you to procs,
tracks your cooldowns, replaces the XP bar with one themed to your talent tree, and
handles the small chores of leveling.

## Install

Copy the `MageEverything` folder into your Forever AddOns directory:

```
World of Warcraft/_forever_/Interface/AddOns/MageEverything
```

Restart the game (or `/reload`). The addon only activates on a Mage.

## What it does

| Part | What you see |
|---|---|
| **Next-spell HUD** | A large icon for the spell to cast now, the next two beside it, the keybind on each icon, and a one-line reason ("Frozen - shatter", "Heating Up x3", "AoE - cone"). The icon turns red when the target is out of range. |
| **Reaction icon** | To the left of the main icon: Counterspell when your target starts casting, Frost Nova when an enemy turns on you, Ice Barrier / Mana Shield, Evocation when you run dry. |
| **Low-health alert** | A pulsing red icon with your best defensive (Ice Barrier, Ice Block, Frost Nova, Mana Shield, Blink) when health drops under the threshold. A "LOW MANA" line does the same for mana. |
| **Cooldown row** | Your main cooldowns with swipe timers; each one flashes and pops when it comes back. |
| **Proc banners** | Animated banners for Missile Barrage, Fingers of Frost, Heating Up, Clearcasting, the shatter window after Frost Nova, level-ups and newly learned spells. |
| **Mage XP bar** | Arcane (violet), Fire (orange) or Frost (blue) theme with its own animation speed. Shows rested XP, XP waiting in completed quests, XP per hour, time to level and kills to level. Hover for a full breakdown. |
| **Reminders** | Out of combat, clickable buttons appear for missing Arcane Intellect, missing armor spell, no conjured water, no mana gem, and "drink" when mana is low. Clicking casts the spell. |
| **Portal menu** | `/mage portals`: left-click a city to teleport, right-click for a portal. |
| **Vendors** | Sells junk and repairs automatically. |

### Rotations

The spec is read from where your talent points are spent, so the list changes by itself
when you respec or swap dual spec. `/mage spec fire` forces one.

- **Levels 1-9**: Frostbolt (or Fireball) at range, Fire Blast when ready, wand when out of mana.
- **Frost**: Frostbolt opener and filler; Ice Lance on Fingers of Frost or inside the shatter
  window after Frost Nova; Cone of Cold / Blizzard / Arcane Explosion on packs; instants while moving.
- **Fire**: Pyroblast opener; Fire Blast to build Heating Up, Pyroblast at 3 stacks; Combustion on
  elites and multi-pulls; Scorch to 5 stacks on elites; Flamestrike / Blast Wave on packs;
  Frostfire Bolt (or Fireball) filler.
- **Arcane**: Arcane Missiles on Missile Barrage or Clearcasting; Arcane Power on elites and
  multi-pulls; Presence of Mind into Arcane Wrath (or Pyroblast); Arcane Blast filler with a stack counter.

"AoE" starts at 3 enemies in combat by default (changeable in options).

## Commands

```
/mage                 options panel
/mage unlock | lock   move the frames (drag the blue boxes)
/mage reset           put frames back
/mage portals         teleport / portal menu
/mage spec auto|arcane|fire|frost
/mage diag            print what the client lets the addon read
/mage on | off        enable / disable (then /reload)
```

## What the game does not allow

WoW Forever runs on the modern client, which restricts combat addons. This shapes the design:

- **No addon can press buttons for you.** Casting and targeting must come from a key press or
  click. The HUD shows the key to press; it cannot press it.
- **In combat the client hides exact health, mana, buffs and debuffs from addons.** The engine
  therefore works from what stays readable: whether a spell is usable or on cooldown, Blizzard's
  proc-glow events, your own casts, how many enemies are in combat, and whether your target is
  attacking you. Things it cannot see are remembered from your own casts instead (for example,
  Frost Nova opens an 8 second shatter window; three Fire Blasts mean Heating Up is ready).
- **Health and mana alerts** are drawn by the client from a threshold curve, so they work even
  though the addon never sees the numbers.
- **Enemy debuffs** (Fire Vulnerability stacks, whether a mob is really still frozen) are estimates
  from your own casts. A root broken early by damage is not detected.
- Forever does not include Blizzard's rotation assistant. If a later patch adds it, turn on
  "Prefer Blizzard's assistant when offered" in the options.

## Status

Written against Blizzard's published UI source for build 1.60.1.70938 and exercised with a
simulated game API. **It has not been run inside the game client.** After installing, run
`/mage diag` once out of combat and once in combat: it lists which spells were found in your
spellbook, the detected spec, and what the client is hiding. Spells are matched by name from
your spellbook, so new ranks are picked up automatically; the new Forever spells
(Arcane Wrath, Frostfire Bolt, Ice Lance, Arcane Blast) are matched the same way.

The default XP bar is hidden by default, which also hides the default reputation bar; untick
"Hide the default XP bar" and `/reload` to get it back.

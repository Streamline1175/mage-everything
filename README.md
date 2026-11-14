# Mage Everything

<img src="logo.png" width="160" alt="Mage Everything logo">

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
| **Reaction icon** | To the left of the main icon: Counterspell when your target (or focus) starts casting, Frost Nova when an enemy turns on you, Ice Barrier / Mana Shield, Cold Snap, Polymorph, and a mana gem or Evocation when you run dry. |
| **Low-health alert** | A pulsing red icon with your best defensive (Ice Barrier, Ice Block, Frost Nova, Mana Shield, Blink) when health drops under the threshold. A "LOW MANA" line does the same for mana. |
| **Cooldown row** | Your main cooldowns with swipe timers; each one flashes and pops when it comes back. |
| **Proc banners** | Animated banners for Missile Barrage, Fingers of Frost, Heating Up, Clearcasting, the shatter window after Frost Nova, level-ups and newly learned spells. |
| **Mage XP bar** | Arcane (violet), Fire (orange) or Frost (blue) theme. Energy flows through the fill, motes drift off it (embers rise fast for Fire, frost falls slowly), an orb spins at the leading edge and "+XP" numbers float up on each gain. Outlined text shows level, XP and percent; a line above shows rested XP, quest XP waiting, XP per hour, time to level and kills to level. Hover for a full breakdown. |
| **Polymorph** | A countdown icon started by your own Polymorph cast, a banner before it ends, and a prompt to sheep the add when a second enemy joins. The game hides the debuff itself, so a sheep that breaks early is not detected. |
| **Wand** | A "Wand finish" badge fades in when your target is nearly dead; a reminder appears if no wand is equipped. |
| **Reminders** | Out of combat, clickable buttons appear for missing Arcane Intellect, missing armor spell, no conjured water or food, no mana gem, a curse on you, and Drink / Eat buttons that use your best conjured water and food (shown only when mana or health is low; Undead also get a Cannibalize button). Info icons flag a missing wand and spells or ranks waiting at the trainer (hover for the list). |
| **Trainer** | When a level unlocks new spells or ranks, a banner and a chat line list them. |
| **Portal menu** | `/mage portals`: left-click a city to teleport, right-click for a portal. |
| **Vendors** | Sells junk and repairs automatically. |

### Rotations

The spec is read from where your talent points are spent, so the list changes by itself
when you respec or swap dual spec. `/mage spec fire` forces one.

- **Levels 1-9**: Frostbolt (or Fireball) at range, Fire Blast when ready, wand when out of mana.
- **Frost**: Frostbolt opener and filler; Ice Barrier kept up (it also raises Frost damage);
  on Fingers of Frost, Frostbolt then Ice Lance right behind it; Ice Lance inside the shatter
  window after Frost Nova; Cone of Cold at 5 Winter's Chill stacks when the enemy is on you;
  Cone of Cold / Blizzard / Arcane Explosion on packs; Cold Snap when Nova and Barrier are both spent.
- **Fire**: Pyroblast opener; Pyroblast again at 3 Heating Up stacks (a 1.5 second cast, so not
  while moving); Combustion on elites and multi-pulls; Scorch to 5 stacks on elites and refreshed
  before it expires; Fire Blast on cooldown; Frostfire Bolt filler (Fireball is an option).
- **Arcane**: Arcane Missiles on Missile Barrage; Clearcasting spent on the most expensive spell;
  Arcane Power on elites and multi-pulls; Presence of Mind into Arcane Wrath; Arcane Blast to
  3 stacks, then cheaper spells until the buff drops (4 stacks only during burst).

"AoE" starts at 3 enemies in combat by default (changeable in options).

## Commands

```
/mage                 options panel
/mage unlock | lock   move the frames (drag the blue boxes)
                      - opening the game's Edit Mode shows the same blue boxes
                      - Shift-drag the XP bar to move it at any time
/mage reset           put frames back
/mage demo            play sample content in every section, for arranging the layout
/mage portals         teleport / portal menu
/mage spec auto|arcane|fire|frost
/mage diag            show what the client lets the addon read, in a window you can copy from
/mage profile         per-character settings: list, share, copy, reset
/mage welcome         setup guide (opens by itself on first install and after updates)
/mage on | off        enable / disable (then /reload)
```

## What the game does not allow

WoW Forever runs on the modern client, which restricts combat addons. This shapes the design:

- **No addon can press buttons for you.** Casting and targeting must come from a key press or
  click. The HUD shows the key to press; it cannot press it.
- **The client hides exact health and mana from addons at all times, and buffs and debuffs in combat.** The engine
  therefore works from what stays readable: whether a spell is usable or on cooldown, Blizzard's
  proc-glow events, your own casts, how many enemies are in combat, and whether your target is
  attacking you. Two more readable signals stand in for hidden buffs: a spell's current **mana
  cost** (Arcane Missiles costing nothing means Missile Barrage; everything costing nothing means
  Clearcasting; Arcane Blast's cost doubles per stack) and its current **cast time** (Pyroblast
  gets 25% faster per Heating Up stack). Other things are remembered from your own casts, such
  as the 8 second shatter window after Frost Nova.
- **Fingers of Frost has no such signal.** It is only detected when the client lets the addon
  read that buff; if `/mage diag` shows it as hidden in combat, the addon cannot see it there.
  Frostbite freezes are likewise invisible.
- **Health and mana alerts** are drawn by the client from a threshold curve, so they work even
  though the addon never sees the numbers.
- **Enemy debuffs** (Fire Vulnerability stacks, whether a mob is really still frozen) are estimates
  from your own casts. A root broken early by damage is not detected.
- Forever does not include Blizzard's rotation assistant. If a later patch adds it, turn on
  "Prefer Blizzard's assistant when offered" in the options.

## Status

Spell IDs, ranks, cooldowns, durations, proc buffs, teleports and conjured items were checked
against the datamined tables for Forever build 1.60.1.70938 (wago.tools) and Wowhead's Forever
tooltips. The API usage was checked against Blizzard's published UI source for the same build.
The priority lists follow the confirmed spell mechanics; guide advice (Icy Veins, Wowhead guides)
could only be read as search snippets because those pages block automated access.

The addon has been exercised with a simulated game API. **It has not been run inside the game
client.** After installing, run `/mage diag` once out of combat and once in combat: it lists
which spells were found in your spellbook, the detected spec, what the client is hiding, and
the stack counts it is currently reading.

Spells are matched by name from your spellbook, so new ranks are picked up automatically.

The default XP bar is hidden by default, which also hides the default reputation bar; untick
"Hide the default XP bar" and `/reload` to get it back.

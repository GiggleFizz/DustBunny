# DustBunny

A destruction queue for **World of Warcraft 3.3.5a (build 12340)** — the
spirit of TSM's Destroying window, era-native. Everything in your bags that
can be **Disenchanted, Milled, or Prospected**, in one craft-style window:
select an item, click the button, watch it become dust, pigment, or gems.

Built for private-server play (AzerothCore), publishable conscience included:
the one item class it will never touch is Legendary.

## Features

### Three trades, one window
A craft-frame-styled window with authentic SpellBook-style icon tabs down the
right edge — Disenchant, Milling, Prospecting (icons taken live from your own
spellbook), plus an Excluded tab. Rows are colored by item rarity and show
your live stack counts; a status line shows the relevant profession skill.

### Honest one-click casting
Each click of the action button performs exactly **one** cast — that's the
3.3.5 client's own law (addons cannot legally auto-loop casts), and DustBunny
doesn't pretend otherwise. Select a stack, click in rhythm, and it drains;
when an item runs out, selection advances to the next row so you can keep
clicking. Casting follows all normal rules: moving interrupts, results
auto-loot into your bags.

Safety details you'll never notice working:
- Clicking during the GCD does **nothing** (without the guard, the underlying
  macro would try to *equip* your disenchant fodder — you're welcome).
- Mid-cast, the targeted stack stays listed but can't be re-targeted, so the
  selection never wanders off while you work.
- Milling and Prospecting honor the 5-per-stack rule; short stacks show but
  can't fire.

### What gets listed — the server's own word
The item lists are generated from the game's actual data (disenchantability,
millable/prospectable flags, loot tables) — no tooltip guesswork:
**18,388** disenchantable items, **45** herbs, **10** ores.

Six items the game *flags* as destroyable but that yield literally nothing
(five vendor Powders and Crinkly Grass) are deliberately fenced out. You
cannot mill Crinkly Grass into the void on our watch.

### Legendary protection — and only Legendary
Legendaries are absent from the data by generation *and* blocked at runtime.
Everything below that is your own business: accidentally dusting an epic is
a rite of passage, not a support ticket.

### Permanent exclusions
Right-click any row to exclude that item forever (per account). The Excluded
tab lists your exclusions; right-click there to restore. Survives reloads,
sessions, and second thoughts.

### Snappable launcher button
A launcher button opens the window like any craft skill: left-click opens,
right-drag moves, and dropping it on an empty action-bar slot snaps it
pixel-perfect into place (it politely refuses occupied slots and visibly
pops clear). Position persists. Works with the stock bars and ButtonForge —
no dependencies.

## Installation
1. Download / clone this repository.
2. Copy the `DustBunny` folder into `Interface/AddOns/`.
3. Full client restart on first install; `/reload` suffices for updates.

## Commands
| Command | Effect |
|---|---|
| `/dustbunny` or `/db` | open/close the window |

## Notes & limitations
- One click per cast is a client restriction, not a design choice — no addon
  can legally do better on 3.3.5, and ones that appear to are worth
  distrusting.
- Item lists reflect stock AzerothCore data; a heavily customized server's
  exotic items may not appear.
- The window rebuilds from your bags live; bank contents are not scanned.

## Compatibility
Built and tested on client build 12340 (3.3.5a) against AzerothCore.
Pure client addon — no server-side component, no dependencies.

## Development
Written by GiggleFizz with AI assistance (Anthropic's Claude) — every line &
feature designed, reviewed, and tested by a human. Issues and PRs welcome.

<!-- Screenshots wanted: the window mid-dust; the launcher snapped to a bar. -->

## License
MIT — see [LICENSE](LICENSE).

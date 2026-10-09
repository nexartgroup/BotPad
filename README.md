# BotPad

**Minimal control panel for Playerbot self-mode and Carbonite-target teleporting in World of Warcraft 3.3.5a (WotLK).**

BotPad is a lightweight WoW addon designed for servers running **mod-playerbots** and **mod-autotravel**. It provides a small in-game control panel for toggling the Playerbot self-mode, selecting bot behavior presets, and teleporting to the current Carbonite destination.

The addon targets the **3.3.5a client (Interface 30300)** and stores its settings per character. 

## Features

* 🎮 **Playerbot self-mode toggle**

  * Enable or disable the Playerbot self-mode directly from the UI.
  * Detects the server's confirmation messages to keep the displayed state synchronized.

* ⚙️ **Bot behavior presets**

  * **BuffBot** — focused on buffing/healing with minimal autonomous behavior.
  * **Minimal** — limited autonomous actions and no normal gathering/looting.
  * **Normal** — standard Playerbot behavior.
  * **Grind** — normal behavior plus autonomous target selection.
  * **Grind&Loot** — grind mode with full looting.

* 📍 **Carbonite teleport**

  * Uses the active Carbonite destination as the teleport target.
  * Converts Carbonite's coordinates into the WoW map coordinates required by `mod-autotravel`.
  * Optional confirmation dialog before teleporting.

* 🗺️ **Automatic map resolution**

  * Builds a zone-name → WorldMapArea ID mapping from the client rather than relying on a hard-coded localization table.
  * Supports a manually forced map ID when automatic resolution is insufficient. 

* 🖥️ **Minimal UI**

  * Movable, compact control panel.
  * Status indicator for Playerbot self-mode.
  * Mode selector and controls for the main BotPad functions.
  * Uses WoW's built-in UI assets; no additional graphics are required. 

* 🔧 **Settings page**

  * **Interface → AddOns → Botpad** (or `/bp optionen`, the `..` button in the panel header, Shift+click on the minimap button).
  * Check boxes for the panel, the minimap button, resetting strategies on stop, hiding the command echoes, the teleport confirmation and debug output; buttons for the mode; fields for the toggle command and a forced map ID; a button that resets everything.
  * Shows the server-module connection, the self-mode state and whether Carbonite was found.

* 💬 **Slash commands**

  * `/botpad`
  * `/bp`
  * `/bp info` — version, module connection, teleport permission, self-mode state
  * `/bp optionen` — open the settings page; `/bp standard` — reset all settings
  * `/bp knopf` (minimap button), `/bp strategien` (reset strategies on stop), `/bp verbergen` (hide command echoes) — toggles for the matching settings

* 🔇 **Chat filtering**

  * With *Hide bot commands* on (`HideCommands`, the default) BotPad hides its own Playerbot commands and the server module's `[AT]` protocol lines from normal chat. The module's text messages (`[AT]M`) are shown once, with the "Botpad:" prefix.
  * With the option off, nothing is hidden: the raw `[AT]` lines appear in chat as well, so module messages show up twice.

## Requirements

BotPad is an **addon**, not a standalone Playerbot implementation.

You need:

* World of Warcraft **3.3.5a / WotLK**
* A server running **mod-playerbots**
* **Carbonite** for the teleport destination feature
* **mod-autotravel** for server-side teleportation

Carbonite is an optional addon from WoW's addon-loader perspective, but it is required if you want to use `/bp tp`. The addon explicitly declares `mod-autotravel` as a server-module requirement. 

## Installation

Clone or download the repository:

```bash
git clone https://github.com/nexartgroup/BotPad.git
```

Copy the `BotPad` directory into your WoW 3.3.5a addons directory:

```text
World of Warcraft/
└── Interface/
    └── AddOns/
        └── BotPad/
            ├── Botpad.toc
            ├── BP_Bot.lua
            ├── BP_Carbonite.lua
            ├── BP_Core.lua
            ├── BP_MapIds.lua
            ├── BP_Options.lua
            └── BP_UI.lua
```

Restart the game or reload the UI.

On login, BotPad initializes its per-character configuration and displays its version in chat. 

## Usage

### Open the control panel

```text
/bp
```

or:

```text
/botpad
```

Running the command without arguments toggles the BotPad window.

### Open the settings

```text
/bp optionen
```

The page lives under **Interface → AddOns → Botpad**. Everything on it can also be set with a slash command; both ways change the same saved variables. `/bp standard` resets all settings to their defaults (the window position, the minimap button position and whether the panel is shown stay as they are).

### Toggle Playerbot self-mode

```text
/bp bot
```

BotPad sends the configured self-mode command to the server and waits for the server's response to determine whether Playerbot is enabled or disabled.

The command is a **toggle**: the same call switches self-mode on and off. The
default is:

```text
.playerbots bot self
```

`playerbots` is the plural name mod-playerbots registers; AzerothCore only
matches the full command name, so the older spelling `.playerbot` is simply an
unknown command (for a normal player the server answers "There is no such command").
Older BotPad versions shipped that spelling as the default — if you never changed
it, it is replaced automatically on load.

If your server uses a different command, it can be changed with:

```text
/bp befehl <command>
```

BotPad reads the server's answer instead of guessing the state. Both current
(`SelfBot is now active.` / `SelfBot is now deactivated.`) and older
(`Enable player botAI` / `Disable player botAI`) texts are recognised. The server
may also **refuse** self-mode (`SelfBot is disabled server-wide.` /
`SelfBot is restricted for this account.`): `AiPlayerbot.SelfBotLevel` defaults to
`1`, which means game masters only. BotPad then tells you why and discards the
strategy commands it had queued.

### Select a bot mode

List available modes:

```text
/bp modus
```

Select one:

```text
/bp modus minimal
/bp modus normal
/bp modus grind
```

The addon also contains `buffbot` and `grind_loot` presets.

When a mode is active, BotPad configures the Playerbot `nc`, `co` and `ll` strategies for that preset.

Note that `ll` (loot strategy) only knows `all`, `gray` and `disenchant`; mod-playerbots
treats every other value as `normal`. What limits looting in *BuffBot* and *Minimal* is
therefore the `nc` strategies `-loot` and `-gather`, not `ll`. (Earlier versions also
sent `ss self`, which is the *skip spells* command and only added a spell called
"self" to that list; it is gone.)

### Teleport to the Carbonite target

```text
/bp tp
```

or:

```text
/bp teleport
```

BotPad reads the final destination from Carbonite, converts its coordinates to normalized zone coordinates, resolves the corresponding WoW map ID, and sends the resulting teleport request to `mod-autotravel`. 

**The server decides who may teleport.** By default `.at tp` needs game-master
rights (`AutoTravel.TeleportSecurity = 2`). BotPad asks the module first and
refuses to send the command if it is not allowed for your account, saying why.

**Handshake first.** BotPad sends `.at hello` the first time you teleport and
sends `.at tp` only after the module has answered. Without the module AzerothCore
answers every `.at ...` command with "There is no such command", and on servers
with `AllowPlayerCommands = 0` (not the default) it treats an unknown dot-command as
ordinary chat, so the coordinates would be said in /say. The handshake also tells
BotPad what your account may do. If the module does not answer, nothing is sent and
you get a warning; the next attempt asks again.

By default, BotPad asks for confirmation before teleporting.

To toggle the confirmation dialog:

```text
/bp nachfrage
```

## Map troubleshooting

If BotPad cannot automatically determine the correct map ID, you can force one:

```text
/bp karte <id>
```

For example:

```text
/bp karte 0
```

resets the setting to automatic map detection.

Enable debug output with:

```text
/bp debug
```

This can help diagnose coordinate conversion, Playerbot commands, and server responses.

## Configuration

BotPad stores configuration in the per-character `BotpadDB` saved variable.

Default settings include:

| Setting        |               Default | Description                        |
| -------------- | --------------------: | ---------------------------------- |
| `Mode`         |              `normal` | Active Playerbot mode              |
| `SelfCommand`  | `.playerbots bot self` | Command used to toggle self-mode  |
| `HideCommands` |                   `1` | Hide BotPad command echoes         |
| `ResetOnStop`  |                   `1` | Reset bot strategies when stopping |
| `ConfirmTp`    |                   `1` | Ask before teleporting             |
| `MinimapAngle` |                 `160` | Minimap button position (degrees)  |
| `MinimapButton` |                  `1` | Show the minimap button            |
| `Shown`        |                   `1` | Whether the panel is visible       |
| `Debug`        |                   `0` | Enable debug messages              |

The panel position is also saved when the window is moved. `ForcedMapId` (see `/bp karte`) is only present while a map ID is forced.

The same values are on the settings page; `/bp standard` (or the reset button there) restores the defaults above and removes `ForcedMapId`. The window position, `MinimapAngle` and `Shown` are kept.

The toggle command (`SelfCommand`, `/bp befehl <text>`) is sent as a chat message, so it must start with a dot (`.playerbots bot self`). Without the dot the character would say it out loud; BotPad refuses such input.

## How teleporting works

Carbonite and `mod-autotravel` use different coordinate representations. BotPad acts as the bridge between them:

```text
Carbonite destination
        │
        ▼
Carbonite map coordinates
        │
        ▼
Normalized zone coordinates
        │
        ▼
WoW WorldMapArea ID
        │
        ▼
mod-autotravel
        │
        ▼
Server-side teleport
```

Carbonite provides the destination and its zone information. BotPad resolves the corresponding WoW map ID and includes the player's current map/position as calibration information. The server module can then perform the actual teleport using the appropriate world coordinates. 

This conversion is necessary because the WoW client does not expose the terrain/collision information needed to determine the correct world-space height for a teleport target. 

## Project structure

```text
BotPad/
├── Botpad.toc          # Addon metadata and load order
├── BP_Core.lua         # Configuration, teleport logic, slash commands
├── BP_Bot.lua          # Playerbot modes, commands and state handling
├── BP_Carbonite.lua    # Carbonite destination integration
├── BP_MapIds.lua       # Zone → WoW map ID resolution
├── BP_UI.lua           # In-game control panel
├── BP_Options.lua      # Settings page (Interface → AddOns → Botpad)
├── tests/              # Offline test suite (see "Testing without the game")
└── LICENSE             # GPL-3.0
```

The addon loads the Carbonite and map-resolution modules first, then the Playerbot and core modules, the control panel, and the settings page last (it reads the other modules' state). 

## Troubleshooting

### "Carbonite ist nicht geladen."

Make sure Carbonite is installed and enabled.

The teleport function reads its current destination from Carbonite. If no Carbonite map data is available, BotPad cannot determine the destination. 

### "Kein Carbonite-Ziel gesetzt."

Set a destination in Carbonite before using:

```text
/bp tp
```

### "Keine Antwort von mod-autotravel. Der Teleportbefehl wurde NICHT gesendet"

Make sure **mod-autotravel** is installed and enabled on the server.

BotPad asks the module (`.at hello`) before the first teleport and waits five seconds for the answer. Without one it does not send the teleport command and warns instead.

### "Der Teleport ist dir auf diesem Server nicht erlaubt"

The module only allows `.at tp` from the account level set in `AutoTravel.TeleportSecurity` (default: game master). A game master or administrator can lower it.

### "Der Server verweigert den Selbstmodus"

The Playerbot self-mode is restricted by the server (`AiPlayerbot.SelfBotLevel`; `0` = off, `1` = game masters only, default). Ask your server administrator.

### "AutoTravel ist ebenfalls geladen"

Use either BotPad or AutoTravel for the Playerbot, not both: each would send the bot its own strategy set every time self-mode switches on. When BotPad finds AutoTravel it stops sending strategies (mode, reset on stop); teleport and the toggle keep working.

In that case BotPad also leaves the server module's text messages and protocol lines to AutoTravel: it neither prints the messages a second time nor hides the lines (AutoTravel's own "hide protocol lines" setting decides). The settings page shows a notice and greys out the mode buttons and "reset strategies on stop".

BotPad detects AutoTravel only by whether it is loaded, not by its settings. If you switched AutoTravel's own bot control off (`BotControl = 0`) BotPad still leaves the strategies alone; disable AutoTravel instead if you want BotPad to manage them.

### Playerbot toggle does not work

Check the command configured for self-mode:

```text
/bp befehl
```

The default is:

```text
.playerbots bot self
```

If your server uses a different Playerbot command syntax, configure it accordingly.

You can also enable debugging:

```text
/bp debug
```

## Changes in 1.2

* **Settings page** under Interface → AddOns → Botpad (see above); new setting `MinimapButton`; `/bp optionen`, `/bp standard`.
* **No more doubled messages** (with *Hide bot commands* on). The text messages of the server module were printed twice (the raw `[AT]M|…` line and again with the "Botpad:" prefix). BotPad now hides the raw line when it prints it itself; with AutoTravel loaded it prints nothing and filters nothing, AutoTravel does. With the option off the raw lines stay visible, by design.
* **Mode lock with AutoTravel.** Choosing a mode (panel dropdown, `/bp modus`, settings page) is refused with a notice while AutoTravel is loaded; the panel dropdown keeps showing the saved mode.
* **With AutoTravel loaded** switching the bot off no longer sends `nc !` / `co !` / `ll normal` (BotPad does not manage strategies then).
* **`/bp befehl` and the settings field refuse a command without a leading dot** (`.` or `!` followed by the command name), which the client would send as ordinary chat. A saved command without a valid prefix is replaced by the default on load.
* **Minimap button** can be hidden (`MinimapButton`, `/bp knopf`); Shift+click on it opens the settings, right click toggles the window, left click toggles the bot.
* **`/bp standard`** also re-applies the default mode to a running bot.

## Compatibility

BotPad is currently targeted specifically at:

```text
WoW Client:       3.3.5a
Interface:        30300
Playerbot:        mod-playerbots
Teleport:         mod-autotravel (protocol 3 or newer)
Optional addon:   Carbonite
```

The addon uses the WoW 3.3.5a UI API and is not intended for modern WoW clients without modification. 

## Testing without the game

```bash
tests/check.sh
```

Needs `lua5.1` (the version WoW 3.3.5a uses) and, optionally, `luacheck`. It runs
`luacheck` (finds names that do not exist, such as a call to a function declared
further down the file), a syntax check, and `tests/run.lua`, which loads the addon
into a mock of the WoW API (`tests/mock_wow.lua`) and checks the handshake before
teleport, the recognition of Playerbot messages, the toggle sequence, the mode
dropdown, the settings page (check boxes, mode buttons, input fields, reset,
opening) and the AutoTravel conflict handling.

This does **not** check how anything looks, or that the real client API behaves
like the mock. It does not replace testing in the game.

## License

BotPad is licensed under the **GNU General Public License v3.0**.



## Links

* NEEDED:[mod-autotravel](https://github.com/nexartgroup/mod-autotravel)
* NEEDED:[mod-playerbots](https://github.com/mod-playerbots/mod-playerbots)
* NEEDED 3.3.5a WOTLK VERSION:[Carbonite](https://www.curseforge.com/wow/addons/carbonite)

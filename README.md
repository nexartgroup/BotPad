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

* 💬 **Slash commands**

  * `/botpad`
  * `/bp`

* 🔇 **Chat filtering**

  * Hides BotPad's own Playerbot commands and relevant server-module protocol messages from normal chat when enabled.

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

### Toggle Playerbot self-mode

```text
/bp bot
```

BotPad sends the configured self-mode command to the server and waits for the server's response to determine whether Playerbot is enabled or disabled.

The default command is:

```text
.playerbot bot self
```

If your server uses a different command, it can be changed with:

```text
/bp befehl <command>
```

For example:

```text
/bp befehl .playerbots bot self
```

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

When a mode is active, BotPad configures the Playerbot `nc`, `co`, `ll`, and `ss` strategies for that preset. 

### Teleport to the Carbonite target

```text
/bp tp
```

or:

```text
/bp teleport
```

BotPad reads the final destination from Carbonite, converts its coordinates to normalized zone coordinates, resolves the corresponding WoW map ID, and sends the resulting teleport request to `mod-autotravel`. 

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
| `SelfCommand`  | `.playerbot bot self` | Command used to toggle self-mode   |
| `HideCommands` |                   `1` | Hide BotPad command echoes         |
| `ResetOnStop`  |                   `1` | Reset bot strategies when stopping |
| `ConfirmTp`    |                   `1` | Ask before teleporting             |
| `MinimapAngle` |                 `210` | Minimap position setting           |
| `Shown`        |                   `1` | Whether the panel is visible       |
| `Debug`        |                   `0` | Enable debug messages              |

The panel position is also saved when the window is moved. 

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
├── BP_UI.lua            # In-game control panel
└── LICENSE             # GPL-3.0
```

The addon loads the Carbonite and map-resolution modules before the Playerbot, core, and UI modules. 

## Troubleshooting

### "Carbonite ist nicht geladen."

Make sure Carbonite is installed and enabled.

The teleport function reads its current destination from Carbonite. If no Carbonite map data is available, BotPad cannot determine the destination. 

### "Kein Carbonite-Ziel gesetzt."

Set a destination in Carbonite before using:

```text
/bp tp
```

### "Keine Antwort vom Server."

Make sure **mod-autotravel** is installed and enabled on the server.

BotPad waits for an `[AT]` response after sending the teleport request. If no response arrives within the expected period, it warns that the server module may be missing or inactive. 

### Playerbot toggle does not work

Check the command configured for self-mode:

```text
/bp befehl
```

The default is:

```text
.playerbot bot self
```

If your server uses a different Playerbot command syntax, configure it accordingly.

You can also enable debugging:

```text
/bp debug
```

## Compatibility

BotPad is currently targeted specifically at:

```text
WoW Client:       3.3.5a
Interface:        30300
Playerbot:        mod-playerbots
Teleport:         mod-autotravel
Optional addon:   Carbonite
```

The addon uses the WoW 3.3.5a UI API and is not intended for modern WoW clients without modification. 

## License

BotPad is licensed under the **GNU General Public License v3.0**.



## Links

* NEEDED:[mod-autotravel](https://github.com/nexartgroup/mod-autotravel)
* NEEDED:[mod-playerbots](https://github.com/mod-playerbots/mod-playerbots)
* NEEDED 3.3.5a WOTLK VERSION:[Carbonite](https://www.curseforge.com/wow/addons/carbonite)

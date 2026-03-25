# Remote Go Brr

A Roblox remote event auto-fire tool with a built-in remote spy, scanner, and per-remote tuning.

## Features

- **Auto-Fire Engine** - Hook any `RemoteEvent` or `UnreliableRemoteEvent` and fire it on a loop with configurable interval
- **Remote Spy** - Intercept and log all remote calls made by the game, then hook captured remotes directly
- **Browse & Scan** - Scan any path (or the entire game) for firable remotes and hook them by index
- **Per-Remote Tuning** - Set custom arguments, individual fire intervals, and burst limits per remote
- **Min/Max Interval** - Randomize fire timing between a min and max millisecond range
- **Profiles** - Save and load hook configurations across sessions
- **Keybinds** - Configurable hotkeys for every major action
- **Auto-Persistence** - Hooked remotes and exclude lists are saved and restored automatically
- **Anti-AFK** - Optional idle prevention

## Installation

Paste into your executor:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Margeshy/Remote-Go-Brr/refs/heads/main/Remote_Go_Brr.lua"))()
```

Or load the file directly if your executor supports `dofile`.

## Usage

### Tabs

| Tab | Purpose |
|---|---|
| **Main** | Toggle auto-fire, config interval and random range, view hooked remotes, and per-remote tuning |
| **Browse** | Scan a path for remotes, show non-firable remotes, hook by index, copy FireServer code |
| **Spy** | Start/stop the remote spy, view captures, exclude list, hook from results |
| **Settings** | Profiles (snapshot save/load), Keybind configuration, and Anti-AFK toggle |

### Keybinds (default)

| Key | Action |
|---|---|
| `F` | Toggle auto-fire ON/OFF |
| `G` | Scan remotes |
| `H` | Start/Stop spy |
| `X` | Clear all hooked remotes |
| `C` | Copy spy results to clipboard |
| `Left Ctrl` | Toggle UI visibility |

All keybinds work globally by default. Disable "Global Keybinds" in Settings to restrict them to when the UI is open.

### Per-Remote Tuning

1. Go to **Main > Per-Remote Tuning**
2. Enter the remote name or its index number from the hooked list
3. Choose what to change:
   - **Set Arguments**: Define exactly what data is sent (e.g. `true, 1, "test"`). Leave blank for none.
   - **Set Interval (ms)**: Overrides the global speed for this specific remote.
   - **Set Burst Limit**: Fires the remote exactly X times, then automatically unhooks it.
4. Enter the value and press Enter

### Profiles

- **Save**: Select "Save" from the dropdown, type a name, and press Enter. 
- **Load**: Select the profile from the dropdown in the Settings tab. It will automatically load all hooks and settings instantly.
- **Storage**: Profiles are stored in your executor's `workspace/RemoteGoBrr/` folder using the format: `[PlaceID]_profile_[Name].json`.

### Random Range (Jitter)

Enter a range in the format `MIN-MAX` (e.g., `50-200`) in the **Random Range** input on the Main tab. This will randomize the delay between each fire for all hooked remotes. Leave it blank to use the fixed **Base Interval**.

## Requirements

- Executor with `hookmetamethod`, `getnamecallmethod` (for Spy)
- `readfile` / `writefile` (for persistence)
- `setclipboard` (for copy features)

## Credits

Built with [Rayfield](https://docs.sirius.menu/rayfield) by Sirius.

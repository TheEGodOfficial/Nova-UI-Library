# NovaUI v1.4 — Complete Reference

> **Client-side only.** Require from a `LocalScript` or a `ModuleScript` called by one.

---

## Table of Contents

1. [Installation](#installation)
2. [Quick Start](#quick-start)
3. [Window](#window)
4. [Components](#components)
   - [Button](#addbutton)
   - [Toggle](#addtoggle)
   - [Slider](#addslider)
   - [TextInput](#addtextinput)
   - [Dropdown](#adddropdown)
   - [MultiDropdown](#addmultidropdown)
   - [ColorPicker](#addcolorpicker)
   - [Keybind](#addkeybind)
   - [Label](#addlabel)
   - [Section](#addsection)
   - [ProgressBar](#addprogress)
5. [Config System](#config-system)
6. [Theme System](#theme-system)
7. [Notifications](#notifications)
8. [Dialogs](#dialogs)
9. [Spring Animation Engine](#spring-animation-engine)
10. [Storage Layer](#storage-layer)
11. [Advanced Patterns](#advanced-patterns)
12. [Full Example](#full-example)

---

## Installation

Place the contents of `NovaUI.lua` inside a `ModuleScript` (e.g. in `ReplicatedStorage`) then require it:

```lua
local Nova = require(game.ReplicatedStorage.NovaUI)
```

No setup calls, no config files. The module is fully self-contained.

### Persistence backends

| Environment | Storage method |
|---|---|
| Executor with `writefile` / `readfile` / `isfile` | Files saved under `NovaUI/` folder |
| Standard Roblox client | `StringValue` instances in `ReplicatedStorage/NovaUI/<namespace>/` (session only) |

### ScreenGui parenting

ScreenGuis are parented automatically: `gethui()` → `CoreGui` → `PlayerGui`.

---

## Quick Start

```lua
local Nova = require(game.ReplicatedStorage.NovaUI)

local win     = Nova.Window{ Title = "My Game", Subtitle = "v1", ToggleKey = Enum.KeyCode.RightShift }
local main    = win:AddTab("Main", "🏠")

main:AddSection("Player")

main:AddToggle{
    Text = "God Mode", Key = "godMode", Default = false,
    Callback = function(v) print("God mode:", v) end,
}

main:AddSlider{
    Text = "Walk Speed", Key = "speed", Min = 16, Max = 200, Default = 16, Increment = 1,
    Callback = function(v)
        local hum = game.Players.LocalPlayer.Character and
                    game.Players.LocalPlayer.Character:FindFirstChild("Humanoid")
        if hum then hum.WalkSpeed = v end
    end,
}

main:AddButton{
    Text = "Say Hello",
    Callback = function() Nova.Notify{ Title = "Hi!", Text = "Button pressed.", Type = "success" } end,
}

local cfg   = win:AddTab("Config", "⚙️")
local theme = win:AddTab("Theme",  "🎨")
cfg:MountConfig()
theme:MountTheme()
```

Press **RightShift** to open the window. The Config tab auto-manages every `Key`-tagged component.

---

## Window

### `Nova.Window(options)` → Window

| Option | Type | Default | Description |
|---|---|---|---|
| `Title` | `string` | `"Nova UI"` | Title bar text. |
| `Subtitle` | `string` | `nil` | Smaller text rendered next to the title. |
| `ToggleKey` | `Enum.KeyCode` | `nil` | Key to open/close the window. Also configurable at runtime from the Theme tab. |
| `Size` | `Vector2` | `Vector2.new(580, 400)` | Window size in pixels; auto-scaled on small viewports. |
| `StartHidden` | `bool` | `false` | If `true` the window starts closed. |
| `StatusText` | `string` | `"NovaUI 1.4.0"` | Initial text in the player profile card. |
| `Gui` | `ScreenGui` | auto | Supply an existing ScreenGui to parent into. |
| `Name` | `string` | `"NovaWindow"` | Name for the auto-created ScreenGui. |

```lua
local win = Nova.Window{
    Title       = "Admin Panel",
    Subtitle    = "v2",
    ToggleKey   = Enum.KeyCode.F4,
    Size        = Vector2.new(640, 480),
    StartHidden = true,
}
```

### Window methods

```lua
win:Open()               -- spring-animated open; no-op if already open
win:Close()              -- spring-animated close
win:Toggle()             -- open if closed, close if open
win:Minimize(state?)     -- collapse to title bar; omit to toggle, true/false to force
win:SetTitle(title, subtitle?)
win:SetStatusText(text?) -- nil resets to "NovaUI 1.4.0"
win:AddTab(name, icon?)  -- returns a Container (see Components)
win:SelectTab(tab)       -- programmatically switch tabs
win:Destroy()            -- disconnect all connections, destroy the GUI
```

```lua
win:SetTitle("My Game", "Round 4")
win:SetStatusText("Spectating")
win:Minimize()       -- toggles
win:Minimize(true)   -- force minimized
```

---

## Components

All component methods live on a **Container** returned by `win:AddTab(...)`.

Every input component returns a handle with:
- `handle.Frame` — the root GuiObject
- `handle:Get()` — current value
- `handle:Set(value)` — set value and fire `Callback`

---

### `AddButton`

Gradient-filled button with a ripple effect.

```lua
tab:AddButton{
    Text     = "Teleport",          -- string, default "Button"
    Callback = function() end,      -- called on click
}
```

**Returns:** `{ Frame, SetText(text) }`

```lua
local btn = tab:AddButton{ Text = "Go", Callback = function() print("clicked") end }
btn:SetText("Done!")
```

---

### `AddToggle`

Animated on/off switch.

```lua
tab:AddToggle{
    Text     = "Infinite Jump",    -- string
    Key      = "infiniteJump",     -- string, registers with the config system
    Default  = false,              -- bool
    Callback = function(v) end,    -- receives bool
}
```

**Returns:** `{ Frame, Get() → bool, Set(bool) }`

```lua
local t = tab:AddToggle{ Text = "Fly", Default = false, Callback = function(v) print(v) end }
t:Set(true)   -- fires Callback(true)
print(t:Get()) --> true
```

---

### `AddSlider`

Draggable range slider.

```lua
tab:AddSlider{
    Text      = "Walk Speed",      -- string
    Key       = "walkSpeed",       -- string
    Min       = 16,                -- number, default 0
    Max       = 200,               -- number, default 100
    Default   = 16,                -- number
    Increment = 1,                 -- snap step, default 1
    Suffix    = " st",             -- appended to the display value, default ""
    Callback  = function(v) end,   -- receives number
}
```

**Returns:** `{ Frame, Get() → number, Set(number) }`

```lua
local s = tab:AddSlider{ Text = "FOV", Min = 70, Max = 120, Default = 90, Suffix = "°",
    Callback = function(v) workspace.CurrentCamera.FieldOfView = v end }
s:Set(100)
```

---

### `AddTextInput`

Single-line text box. `Callback` fires on `FocusLost` (Enter key or click-away).

```lua
tab:AddTextInput{
    Text        = "Player Name",   -- label to the left
    Key         = "playerName",
    Default     = "",              -- initial text
    Placeholder = "Type here…",
    Callback    = function(text, enter) end,  -- enter=true when confirmed
}
```

> `Set(value)` fires `Callback(value, true)`.

**Returns:** `{ Frame, Get() → string, Set(string) }`

```lua
local inp = tab:AddTextInput{ Text = "Server", Placeholder = "IP…",
    Callback = function(text, enter) if enter then print("Connecting to", text) end end }
inp:Set("127.0.0.1")  -- fires Callback("127.0.0.1", true)
```

---

### `AddDropdown`

Single-select dropdown. Options list can be mutated live without closing the dropdown.

```lua
tab:AddDropdown{
    Text     = "Game Mode",
    Key      = "gameMode",
    Options  = { "Casual", "Ranked", "Custom" },
    Default  = "Casual",
    Callback = function(v) end,
}
```

**Returns:** `{ Frame, Get(), Set(value), SetOptions({...}), AddOption(opt), RemoveOption(opt) }`

```lua
local dd = tab:AddDropdown{ Text = "Mode", Options = {"A","B"}, Default = "A",
    Callback = function(v) print(v) end }

dd:AddOption("C")          -- adds without closing
dd:RemoveOption("B")       -- removes; deselects if it was selected
dd:SetOptions({"X","Y"})   -- full replace
dd:Set("X")
print(dd:Get())  --> "X"
```

---

### `AddMultiDropdown`

Multi-select dropdown with checkmarks. `Callback` receives a table of all selected values.

```lua
tab:AddMultiDropdown{
    Text     = "Active Perks",
    Key      = "perks",
    Options  = { "Speed", "Jump", "Damage", "Defense" },
    Default  = { "Speed" },
    Max      = 2,               -- max simultaneous selections; nil = unlimited
    Callback = function(selected) end,  -- receives { "Speed", "Jump" }
}
```

**Returns:** `{ Frame, Get() → {any}, Set({...}), SetOptions({...}), AddOption(opt), RemoveOption(opt) }`

```lua
local m = tab:AddMultiDropdown{ Text = "Flags", Options = {"A","B","C"}, Default = {"A","B"},
    Callback = function(t) print(table.concat(t, ", ")) end }
m:Set({"C"})
print(m:Get())  --> { "C" }
```

---

### `AddColorPicker`

Collapsed color swatch that expands to a full HSV picker (SV square + hue strip + hex input).

```lua
tab:AddColorPicker{
    Text     = "Beam Color",
    Key      = "beamColor",
    Default  = Color3.fromRGB(255, 80, 120),
    Callback = function(c) end,   -- fires continuously while dragging
}
```

**Returns:** `{ Frame, Get() → Color3, Set(Color3) }`

```lua
local cp = tab:AddColorPicker{ Text = "Fog", Default = Color3.fromRGB(180,180,220),
    Callback = function(c) game.Lighting.FogColor = c end }
cp:Set(Color3.fromRGB(255,0,0))
```

---

### `AddKeybind`

Keybind picker. Click to listen, press any key to bind, Escape to cancel, right-click to clear.

```lua
tab:AddKeybind{
    Text     = "Noclip Toggle",
    Key      = "noclipKey",
    Default  = Enum.KeyCode.N,
    Callback = function(key) end,  -- receives Enum.KeyCode
}
```

`Enum.KeyCode.Unknown` is displayed as `None`.

**Returns:** `{ Frame, Get() → Enum.KeyCode, Set(Enum.KeyCode) }`

```lua
local kb = tab:AddKeybind{ Text = "Sprint", Default = Enum.KeyCode.LeftShift,
    Callback = function(k) print("Sprint key:", k.Name) end }
kb:Set(Enum.KeyCode.CapsLock)
```

---

### `AddLabel`

Static word-wrapped text label.

**Returns:** `{ Frame, Set(text) }`

```lua
local lbl = tab:AddLabel("Changes take effect on respawn.")
lbl:Set("Applied immediately.")
```

---

### `AddSection`

Slim uppercase divider header. Returns nothing.

```lua
tab:AddSection("Visuals")
tab:AddSection("Gameplay")
```

---

### `AddProgress`

Read-only progress bar with a gradient fill. Value is `0.0`–`1.0`.

```lua
tab:AddProgress{
    Text  = "XP",
    Value = 0.35,
}
```

**Returns:** `{ Frame, Set(value: 0–1) }`

```lua
local bar = tab:AddProgress{ Text = "Loading", Value = 0 }
bar:Set(0.5)
bar:Set(1.0)
```

---

## Config System

The config system saves and loads values for every component tagged with `Key`. The GUI tab provides Game/Global scope selection, profile CRUD, and auto-load — no scripting required beyond calling `MountConfig()`.

### Setup

Tag components on **any** tab with `Key = "..."` **before** calling `MountConfig()`:

```lua
local main = win:AddTab("Main", "🏠")

main:AddToggle{ Text = "God Mode",  Key = "godMode",  Default = false, Callback = function(v) end }
main:AddSlider{ Text = "Speed",     Key = "speed",    Default = 16,    Callback = function(v) end }
main:AddKeybind{ Text = "Fly Key",  Key = "flyKey",   Default = Enum.KeyCode.F, Callback = function(k) end }

-- Mount the config UI last
local cfgTab = win:AddTab("Config", "⚙️")
cfgTab:MountConfig()
```

### What `MountConfig()` adds to the tab

- **Game / Global toggle** — Game profiles are namespaced by `PlaceId`; Global profiles are shared across all games that use NovaUI.
- **Profile dropdown** — select a saved profile.
- **Profile name input** — type a name for a new profile.
- **Save New** — saves current values under the typed name; prompts to overwrite if the name exists.
- **Overwrite** — overwrites the selected profile with current values.
- **Load** — applies the selected profile's saved values to all registered components.
- **Delete** — removes the selected profile (with confirmation dialog).
- **Reset Defaults** — restores all registered components to their `Default` values.
- **Auto-load** — on startup, the last used profile for the active scope is loaded automatically.

### Scope

| Scope | Storage key | Visibility |
|---|---|---|
| Game | `NovaConfig_<PlaceId>` | This game only |
| Global | `NovaConfig_Global` | All games using NovaUI |

### Manual registration

For components created outside a tab (or without a `Key`):

```lua
local comp = someTab:AddToggle{ Text = "X", Default = false, Callback = function(v) end }
Nova._cfg:Register("myKey", comp, false)  -- (key, component, defaultValue)
```

`Nova._cfg` always points to whichever scope (Game or Global) is currently active in the GUI.

### Supported component types

`AddToggle`, `AddSlider`, `AddTextInput`, `AddDropdown`, `AddMultiDropdown`, `AddColorPicker`, `AddKeybind` all support `Key` auto-registration.

---

## Theme System

The theme system lets users change all UI colors live, save named theme profiles, and bind the window toggle key — entirely through a GUI tab.

### Setup

```lua
local themeTab = win:AddTab("Theme", "🎨")
themeTab:MountTheme()
```

### What `MountTheme()` adds to the tab

- **Toggle Keybind picker** — binds the key used to open/close the window (same as `ToggleKey` on `Nova.Window`).
- **Game / Global scope toggle** — same semantics as the Config system.
- **Preset buttons** — one-click palettes: `Nova Dark`, `Midnight`, `Crimson`, `Ocean`, `Forest`, `Mono`.
- **Color pickers** — one live `AddColorPicker` per theme key (see table below); changes apply to `Nova.Theme` instantly.
- **Saved Themes** — profile selector, name input, Save New, Overwrite, Load, Delete.
- **Auto-load** — restores the last used theme on startup.

### Theme keys

| Key | Role |
|---|---|
| `Background` | Main window background |
| `Surface` | Card and panel backgrounds |
| `SurfaceHover` | Card hover state |
| `Stroke` | Borders and dividers |
| `Accent` | Primary accent (active states, fills) |
| `AccentAlt` | Secondary accent (gradient ends, Global scope) |
| `Text` | Primary text |
| `SubText` | Secondary / muted text |
| `Success` | Success notification / indicators |
| `Warning` | Warning notification / minimize button |
| `Danger` | Error notification / close button |

### Setting the theme from code

```lua
-- Override specific keys at any time:
Nova.SetTheme({
    Accent    = Color3.fromRGB(255, 60, 100),
    AccentAlt = Color3.fromRGB(255, 140, 40),
})
```

### Built-in presets (reference)

| Preset | Accent | AccentAlt |
|---|---|---|
| Nova Dark | `rgb(124, 92, 255)` | `rgb(64, 170, 255)` |
| Midnight | `rgb(90, 60, 220)` | `rgb(40, 130, 220)` |
| Crimson | `rgb(220, 50, 80)` | `rgb(255, 120, 60)` |
| Ocean | `rgb(40, 180, 255)` | `rgb(60, 230, 200)` |
| Forest | `rgb(80, 200, 100)` | `rgb(160, 230, 80)` |
| Mono | `rgb(200, 200, 200)` | `rgb(160, 160, 160)` |

---

## Notifications

### `Nova.Notify(options)` → `{ Dismiss() }`

Slide-in toast notifications that stack at the bottom-right of the screen. Auto-dismiss after `Duration` seconds; click to dismiss early.

| Option | Type | Default | Description |
|---|---|---|---|
| `Title` | `string` | `"Notification"` | Bold title line. |
| `Text` | `string` | `""` | Body text (wraps, truncates at 2 lines). |
| `Type` | `string` | `"info"` | `"info"`, `"success"`, `"warning"`, `"error"` — sets the accent color. |
| `Duration` | `number` | `4` | Seconds before auto-dismiss. |

```lua
Nova.Notify{ Title = "Saved", Text = "Profile saved successfully.", Type = "success", Duration = 3 }
Nova.Notify{ Title = "Error", Text = "Could not connect.", Type = "error" }

-- Manual dismiss:
local n = Nova.Notify{ Title = "Loading…", Text = "Please wait.", Duration = 60 }
task.delay(2, function() n.Dismiss() end)
```

---

## Dialogs

### `Nova.Dialog(options)` → `{ Close() }`

Animated modal dialog with a dim overlay. Clicking outside dismisses it unless `Dismissible = false`.

| Option | Type | Default | Description |
|---|---|---|---|
| `Title` | `string` | `"Dialog"` | Bold heading. |
| `Text` | `string` | `""` | Body message (word-wrapped). |
| `Buttons` | `{{Text, Primary?, Callback?}}` | `{{ Text="OK", Primary=true }}` | Button list rendered right-aligned. `Primary = true` styles with the accent gradient. |
| `Dismissible` | `bool` | `true` | If `false`, clicking the dim overlay does nothing. |

```lua
Nova.Dialog{
    Title   = "Delete profile?",
    Text    = "This cannot be undone.",
    Buttons = {
        {
            Text     = "Delete",
            Primary  = true,
            Callback = function() print("Deleted") end,
        },
        { Text = "Cancel" },
    },
}
```

```lua
-- Non-dismissible (forces a choice):
Nova.Dialog{
    Title       = "Accept Terms",
    Text        = "You must accept before continuing.",
    Dismissible = false,
    Buttons     = {
        { Text = "Accept", Primary = true, Callback = function() startGame() end },
        { Text = "Decline", Callback = function() game:Shutdown() end },
    },
}
```

---

## Spring Animation Engine

NovaUI includes a spring physics engine that drives all its own animations. You can use it to animate any Roblox `GuiObject` property.

### `Nova.Animate(instance, property, target, speed, damping)`

Starts or updates a spring animation toward `target`.

| Parameter | Type | Description |
|---|---|---|
| `instance` | `GuiObject` | The object to animate. |
| `property` | `string` | Property name: `"Size"`, `"Position"`, `"BackgroundColor3"`, etc. |
| `target` | `number / Color3 / UDim2 / Vector2 / UDim` | Target value. |
| `speed` | `number` or `{speed, damping}` | Spring frequency. Higher = snappier. |
| `damping` | `number` | `1.0` = critically damped (no bounce), `< 1` = underdamped (bouncy). |

Supported types: `number`, `Color3`, `UDim2`, `Vector2`, `UDim`.

```lua
-- Animate a frame to a new size:
Nova.Animate(myFrame, "Size", UDim2.fromOffset(200, 100), 24, 0.8)

-- Using a preset table:
Nova.Animate(myFrame, "BackgroundColor3", Color3.fromRGB(255, 0, 0), Nova.Presets.Bouncy)
```

### `Nova.Snap(instance, property, value)`

Instantly sets a property and cancels any running spring on it.

```lua
Nova.Snap(myFrame, "Position", UDim2.fromOffset(0, 0))
```

### Built-in presets

| Preset | Speed | Damping | Feel |
|---|---|---|---|
| `Nova.Presets.Snappy` | 32 | 1.0 | Instant, no bounce |
| `Nova.Presets.Smooth` | 16 | 1.0 | Gentle glide |
| `Nova.Presets.Bouncy` | 24 | 0.55 | Springy overshoot |
| `Nova.Presets.Wobbly` | 14 | 0.38 | Exaggerated wobble |

```lua
Nova.Animate(label, "TextTransparency", 0, Nova.Presets.Smooth)
Nova.Animate(icon,  "Size", UDim2.fromOffset(40, 40), Nova.Presets.Bouncy)
```

---

## Storage Layer

`Nova.Storage` is the low-level persistence API used internally by the Config and Theme systems. You can use it directly for custom save/load logic.

### `Nova.Storage.Save(namespace, key, data)`

Saves a string `data` under `namespace/key`.

### `Nova.Storage.Load(namespace, key)` → `string | nil`

Returns the saved string, or `nil` if not found.

```lua
Nova.Storage.Save("MyGame", "highScore", "9999")
local score = Nova.Storage.Load("MyGame", "highScore")
print(score)  --> "9999"
```

### `Nova.JSON`

A minimal JSON encoder/decoder bundled with NovaUI. Supports `number`, `boolean`, `string`, `nil`, arrays, and dictionaries. Also handles `Color3` (as `{ __type="Color3", hex="RRGGBB" }`) and `Enum.KeyCode` (as `{ __type="KeyCode", name="..." }`) when used through the config serialisation helpers.

```lua
local encoded = Nova.JSON.encode({ speed = 100, fly = true })
-- '{"speed":100,"fly":true}'

local decoded = Nova.JSON.decode(encoded)
print(decoded.speed)  --> 100
```

---

## Advanced Patterns

### Multiple windows

Each call to `Nova.Window()` creates an independent window. They share the same `Nova.Theme` table and spring engine.

```lua
local mainWin  = Nova.Window{ Title = "Main",  ToggleKey = Enum.KeyCode.RightShift }
local adminWin = Nova.Window{ Title = "Admin", ToggleKey = Enum.KeyCode.F9, StartHidden = true }
```

### Programmatic Get / Set on all components

Every input component supports `:Get()` and `:Set(value)`. `Set` always fires `Callback`.

```lua
local toggle = tab:AddToggle{ Text = "Mute", Default = false, Callback = function(v) print(v) end }
local slider = tab:AddSlider{ Text = "Vol",  Default = 50,    Callback = function(v) print(v) end }

-- Read current values:
print(toggle:Get())  --> false
print(slider:Get())  --> 50

-- Set programmatically (fires Callback):
toggle:Set(true)
slider:Set(80)
```

### Live Dropdown mutation

`AddOption`, `RemoveOption`, and `SetOptions` all work while the dropdown is open.

```lua
local dd = tab:AddDropdown{ Text = "Players", Options = {}, Callback = function(v) end }

-- Populate from a remote event:
game.ReplicatedStorage.PlayerList.OnClientEvent:Connect(function(list)
    dd:SetOptions(list)
end)
```

### Registering components manually

Use `Nova._cfg:Register` for components that weren't created with a `Key`, or that were created before `MountConfig` was called on a different tab.

```lua
local comp = someTab:AddToggle{ Text = "X", Default = true, Callback = function(v) end }
Nova._cfg:Register("myExtraKey", comp, true)  -- key, component, default
```

### Player profile card

The sidebar always shows the local player's avatar, display name, and a status line. Update the status line at any time:

```lua
win:SetStatusText("Round 3 — 2 players left")
win:SetStatusText(nil)  -- reset to "NovaUI 1.4.0"
```

### Animating your own GUI

You can use the spring engine on any GuiObject outside of NovaUI windows:

```lua
local frame = script.Parent.MyFrame

Nova.Animate(frame, "Size",             UDim2.fromOffset(300, 200), Nova.Presets.Bouncy)
Nova.Animate(frame, "BackgroundColor3", Color3.fromRGB(30, 30, 50), Nova.Presets.Smooth)
Nova.Animate(frame, "GroupTransparency", 0,                         24, 0.9)

-- Cancel and snap immediately:
Nova.Snap(frame, "Size", UDim2.fromOffset(0, 0))
```

---

## Full Example

A complete LocalScript demonstrating every major feature.

```lua
--!nonstrict
local Nova = require(game.ReplicatedStorage.NovaUI)

-- ── Window ────────────────────────────────────────────────────────────────────
local win = Nova.Window{
    Title      = "Nova Demo",
    Subtitle   = "v1.4",
    ToggleKey  = Enum.KeyCode.RightShift,
    Size       = Vector2.new(600, 420),
}

-- ── Main tab ──────────────────────────────────────────────────────────────────
local main = win:AddTab("Main", "🏠")

main:AddSection("Character")

main:AddToggle{
    Text = "God Mode", Key = "godMode", Default = false,
    Callback = function(v)
        local char = game.Players.LocalPlayer.Character
        if char then
            local hum = char:FindFirstChild("Humanoid")
            if hum then hum.MaxHealth = v and math.huge or 100 end
        end
    end,
}

main:AddSlider{
    Text = "Walk Speed", Key = "speed", Min = 16, Max = 200, Default = 16,
    Suffix = " st", Increment = 2,
    Callback = function(v)
        local char = game.Players.LocalPlayer.Character
        local hum  = char and char:FindFirstChild("Humanoid")
        if hum then hum.WalkSpeed = v end
    end,
}

main:AddSlider{
    Text = "Jump Power", Key = "jump", Min = 50, Max = 500, Default = 50,
    Suffix = "", Increment = 10,
    Callback = function(v)
        local char = game.Players.LocalPlayer.Character
        local hum  = char and char:FindFirstChild("Humanoid")
        if hum then hum.JumpPower = v end
    end,
}

main:AddSection("Visuals")

main:AddColorPicker{
    Text = "Ambient Color", Key = "ambientColor",
    Default = Color3.fromRGB(178, 178, 178),
    Callback = function(c) game.Lighting.Ambient = c end,
}

main:AddToggle{
    Text = "Fullbright", Key = "fullbright", Default = false,
    Callback = function(v)
        game.Lighting.Brightness = v and 2 or 1
    end,
}

main:AddSection("Actions")

main:AddButton{
    Text = "Respawn",
    Callback = function()
        game.Players.LocalPlayer:LoadCharacter()
        Nova.Notify{ Title = "Respawned", Type = "info", Duration = 2 }
    end,
}

main:AddButton{
    Text = "Show Dialog",
    Callback = function()
        Nova.Dialog{
            Title   = "Are you sure?",
            Text    = "This will reset your character.",
            Buttons = {
                { Text = "Yes", Primary = true, Callback = function()
                    game.Players.LocalPlayer:LoadCharacter()
                end },
                { Text = "Cancel" },
            },
        }
    end,
}

-- ── Misc tab ──────────────────────────────────────────────────────────────────
local misc = win:AddTab("Misc", "🔧")

misc:AddSection("Input")

misc:AddKeybind{
    Text = "Noclip Key", Key = "noclipKey", Default = Enum.KeyCode.N,
    Callback = function(k) print("Noclip key set to:", k.Name) end,
}

misc:AddTextInput{
    Text = "Server IP", Key = "serverIp", Placeholder = "e.g. 192.168.1.1",
    Callback = function(text, enter)
        if enter then print("Connect to:", text) end
    end,
}

misc:AddDropdown{
    Text = "Region", Key = "region",
    Options = { "NA", "EU", "ASIA", "SA" },
    Default = "NA",
    Callback = function(v) print("Region:", v) end,
}

misc:AddMultiDropdown{
    Text = "Enabled Modules", Key = "modules",
    Options = { "ESP", "Aimbot", "Speed", "Fly" },
    Default = { "Speed" },
    Callback = function(t) print("Modules:", table.concat(t, ", ")) end,
}

misc:AddSection("Info")

misc:AddProgress{ Text = "XP", Value = 0.65 }
misc:AddLabel("This is a label. It supports word-wrapping for longer text.")

-- ── Config tab ────────────────────────────────────────────────────────────────
local cfgTab = win:AddTab("Config", "⚙️")
cfgTab:MountConfig()

-- ── Theme tab ─────────────────────────────────────────────────────────────────
local themeTab = win:AddTab("Theme", "🎨")
themeTab:MountTheme()

-- ── Update the status line after some game event ──────────────────────────────
task.delay(3, function()
    win:SetStatusText("Round started!")
end)
```

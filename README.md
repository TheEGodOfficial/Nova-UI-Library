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

**Option A — ModuleScript (studio / game scripts)**

Place the contents of `NovaUILib.lua` inside a `ModuleScript` (e.g. in `ReplicatedStorage`) then require it:

```lua
local Nova = require(game.ReplicatedStorage.NovaUI)
```

**Option B — Executor (loadstring)**

```lua
local Nova = loadstring(game:HttpGet("https://raw.githubusercontent.com/TheEGodOfficial/Nova-UI-Library/refs/heads/main/NovaUILib.lua"))()
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

local win  = Nova.Window{ Title = "My Game", Subtitle = "v1", ToggleKey = Enum.KeyCode.RightShift }
local main = win:AddTab("Main", "🏠")

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

> **Bug fix — Minimize:** `Sidebar.Visible` is not toggled by the default `Minimize` implementation.
> Add `self.Sidebar.Visible = not state` inside `Window:Minimize` to hide the profile card and tab list
> when the window is collapsed.

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
    Text     = "Teleport",     -- string, default "Button"
    Callback = function() end, -- called on click
}
```

**Returns:** `{ Frame, SetText(text) }`

```lua
local btn = tab:AddButton{ Text = "Go", Callback = function() print("clicked") end }
btn:SetText("Done!")
```

> **Bug fix — button text invisible:** The `face` frame was a `CanvasGroup`, which composites all
> children into a flat image before rendering. A sibling `hit` TextButton drawn on top of that image
> obscured the label regardless of `ZIndex`. Fix: change `face` from `CanvasGroup` to `Frame`.
> This applies to `AddButton` (line ~562) **and** the shared `actionRow` helper used by the Config
> and Theme tabs (line ~1788).

---

### `AddToggle`

Animated on/off switch.

```lua
tab:AddToggle{
    Text     = "Infinite Jump",
    Key      = "infiniteJump",  -- registers with the config system
    Default  = false,
    Callback = function(v) end, -- receives bool
}
```

**Returns:** `{ Frame, Get() → bool, Set(bool) }`

```lua
local t = tab:AddToggle{ Text = "Fly", Default = false, Callback = function(v) print(v) end }
t:Set(true)
print(t:Get()) --> true
```

---

### `AddSlider`

Draggable range slider.

```lua
tab:AddSlider{
    Text      = "Walk Speed",
    Key       = "walkSpeed",
    Min       = 16,             -- default 0
    Max       = 200,            -- default 100
    Default   = 16,
    Increment = 1,              -- snap step, default 1
    Suffix    = " st",          -- appended to display value, default ""
    Callback  = function(v) end,
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
    Text        = "Player Name",
    Key         = "playerName",
    Default     = "",
    Placeholder = "Type here…",
    Callback    = function(text, enter) end, -- enter=true when confirmed
}
```

> `Set(value)` fires `Callback(value, true)`.

**Returns:** `{ Frame, Get() → string, Set(string) }`

```lua
local inp = tab:AddTextInput{ Text = "Server", Placeholder = "IP…",
    Callback = function(text, enter) if enter then print("Connecting to", text) end end }
inp:Set("127.0.0.1")
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

dd:AddOption("C")
dd:RemoveOption("B")
dd:SetOptions({"X","Y"})
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
    Callback = function(selected) end,
}
```

**Returns:** `{ Frame, Get() → {any}, Set({...}), SetOptions({...}), AddOption(opt), RemoveOption(opt) }`

```lua
local m = tab:AddMultiDropdown{ Text = "Flags", Options = {"A","B","C"}, Default = {"A","B"},
    Callback = function(t) print(table.concat(t, ", ")) end }
m:Set({"C"})
```

---

### `AddColorPicker`

Collapsed color swatch that expands to a full HSV picker (SV square + hue strip + hex input).

```lua
tab:AddColorPicker{
    Text     = "Beam Color",
    Key      = "beamColor",
    Default  = Color3.fromRGB(255, 80, 120),
    Callback = function(c) end, -- fires continuously while dragging
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
    Callback = function(key) end, -- receives Enum.KeyCode
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

Slim uppercase divider header.

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

The config system saves and loads values for every component tagged with `Key`. The GUI tab provides
Game/Global scope selection, profile CRUD, and auto-load — no scripting required beyond calling
`MountConfig()`.

### Setup

Tag components on **any** tab with `Key = "..."`, then call `MountConfig()`, then call
`Nova.AutoLoadConfig()` **last** — after all keyed components have been added.

```lua
local main = win:AddTab("Main", "🏠")

main:AddToggle{ Text = "God Mode", Key = "godMode",  Default = false, Callback = function(v) end }
main:AddSlider{ Text = "Speed",    Key = "speed",    Default = 16,    Callback = function(v) end }
main:AddKeybind{ Text = "Fly Key", Key = "flyKey",   Default = Enum.KeyCode.F, Callback = function(k) end }

local cfgTab = win:AddTab("Config", "⚙️")
cfgTab:MountConfig()

Nova.AutoLoadConfig()  -- call this last, after all keyed components are defined
```

### Known bugs and fixes

#### Bug 1 — Components on other tabs never registered

`MountConfig()` originally patched `Add*` methods only on the config tab itself, so components added
to any other tab were never registered and nothing was saved or loaded.

**Fix:** patch `Container` (the shared metatable) instead of the local tab:

```lua
-- Inside MountConfig(), change:
tab[method] = function(self2, o2, ...)   -- WRONG — only patches the config tab

-- To:
Container[method] = function(self2, o2, ...)  -- CORRECT — patches all tabs
```

#### Bug 2 — AutoLoad runs before components are registered

The original `task.defer(AutoLoad)` inside `MountConfig()` fires before the caller has finished
adding keyed components, so `_entries` is empty and nothing gets applied.

**Fix:** remove the deferred auto-load from `MountConfig()` and expose `Nova.AutoLoadConfig()` to
call manually at the end of your setup script:

```lua
function Nova.AutoLoadConfig()
    task.defer(function()
        local loaded = Nova._cfg:AutoLoad()
        if loaded then
            Nova.Notify{ Title="Config", Text='Auto-loaded "'..loaded..'"', Type="info", Duration=2 }
        end
    end)
end
```

### What `MountConfig()` adds to the tab

- **Game / Global toggle** — Game profiles are namespaced by `PlaceId`; Global profiles are shared.
- **Profile dropdown** — select a saved profile.
- **Profile name input** — type a name for a new profile.
- **Save New** — saves current values under the typed name; prompts to overwrite if it exists.
- **Overwrite** — overwrites the selected profile with current values.
- **Load** — applies the selected profile's saved values to all registered components.
- **Delete** — removes the selected profile (with confirmation dialog).
- **Reset Defaults** — restores all registered components to their `Default` values.
- **Auto-load** — on startup, the last used profile for the active scope is loaded (via `Nova.AutoLoadConfig()`).

### Scope

| Scope | Storage key | Visibility |
|---|---|---|
| Game | `NovaConfig_<PlaceId>` | This game only |
| Global | `NovaConfig_Global` | All games using NovaUI |

### Manual registration

```lua
local comp = someTab:AddToggle{ Text = "X", Default = false, Callback = function(v) end }
Nova._cfg:Register("myKey", comp, false)  -- (key, component, defaultValue)
```

`Nova._cfg` always points to whichever scope is currently active in the GUI.

### Supported component types

`AddToggle`, `AddSlider`, `AddTextInput`, `AddDropdown`, `AddMultiDropdown`, `AddColorPicker`,
`AddKeybind` all support `Key` auto-registration.

---

## Theme System

The theme system lets users change all UI colors live, save named theme profiles, and bind the window
toggle key — entirely through a GUI tab.

### Setup

```lua
local themeTab = win:AddTab("Theme", "🎨")
themeTab:MountTheme()
```

### What `MountTheme()` adds to the tab

- **Toggle Keybind picker** — binds the key used to open/close the window.
- **Game / Global scope toggle** — same semantics as the Config system.
- **Preset buttons** — one-click palettes: `Nova Dark`, `Midnight`, `Crimson`, `Ocean`, `Forest`, `Mono`.
- **Color pickers** — one live `AddColorPicker` per theme key; changes apply to `Nova.Theme` instantly.
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
Nova.SetTheme({
    Accent    = Color3.fromRGB(255, 60, 100),
    AccentAlt = Color3.fromRGB(255, 140, 40),
})
```

### Built-in presets

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

Slide-in toast notifications that stack at the bottom-right of the screen.

| Option | Type | Default | Description |
|---|---|---|---|
| `Title` | `string` | `"Notification"` | Bold title line. |
| `Text` | `string` | `""` | Body text (wraps, truncates at 2 lines). |
| `Type` | `string` | `"info"` | `"info"`, `"success"`, `"warning"`, `"error"` |
| `Duration` | `number` | `4` | Seconds before auto-dismiss. |

```lua
Nova.Notify{ Title = "Saved", Text = "Profile saved successfully.", Type = "success", Duration = 3 }
Nova.Notify{ Title = "Error", Text = "Could not connect.", Type = "error" }

local n = Nova.Notify{ Title = "Loading…", Text = "Please wait.", Duration = 60 }
task.delay(2, function() n.Dismiss() end)
```

---

## Dialogs

### `Nova.Dialog(options)` → `{ Close() }`

Animated modal dialog with a dim overlay.

| Option | Type | Default | Description |
|---|---|---|---|
| `Title` | `string` | `"Dialog"` | Bold heading. |
| `Text` | `string` | `""` | Body message (word-wrapped). |
| `Buttons` | `{{Text, Primary?, Callback?}}` | `{{ Text="OK", Primary=true }}` | Right-aligned button list. |
| `Dismissible` | `bool` | `true` | If `false`, clicking the overlay does nothing. |

```lua
Nova.Dialog{
    Title   = "Delete profile?",
    Text    = "This cannot be undone.",
    Buttons = {
        { Text = "Delete", Primary = true, Callback = function() print("Deleted") end },
        { Text = "Cancel" },
    },
}
```

```lua
Nova.Dialog{
    Title       = "Accept Terms",
    Text        = "You must accept before continuing.",
    Dismissible = false,
    Buttons     = {
        { Text = "Accept",  Primary = true, Callback = function() startGame() end },
        { Text = "Decline", Callback = function() game:Shutdown() end },
    },
}
```

---

## Spring Animation Engine

### `Nova.Animate(instance, property, target, speed, damping)`

| Parameter | Type | Description |
|---|---|---|
| `instance` | `GuiObject` | The object to animate. |
| `property` | `string` | Property name: `"Size"`, `"Position"`, `"BackgroundColor3"`, etc. |
| `target` | `number / Color3 / UDim2 / Vector2 / UDim` | Target value. |
| `speed` | `number` or `{speed, damping}` | Spring frequency. Higher = snappier. |
| `damping` | `number` | `1.0` = no bounce, `< 1` = bouncy. |

Supported types: `number`, `Color3`, `UDim2`, `Vector2`, `UDim`.

```lua
Nova.Animate(myFrame, "Size", UDim2.fromOffset(200, 100), 24, 0.8)
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

`Nova.Storage` is the low-level persistence API used internally by the Config and Theme systems.

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

Minimal JSON encoder/decoder. Supports `number`, `boolean`, `string`, `nil`, arrays, and
dictionaries. Also handles `Color3` (as `{ __type="Color3", hex="RRGGBB" }`) and `Enum.KeyCode`
(as `{ __type="KeyCode", name="..." }`).

```lua
local encoded = Nova.JSON.encode({ speed = 100, fly = true })
-- '{"speed":100,"fly":true}'

local decoded = Nova.JSON.decode(encoded)
print(decoded.speed)  --> 100
```

---

## Advanced Patterns

### Multiple windows

```lua
local mainWin  = Nova.Window{ Title = "Main",  ToggleKey = Enum.KeyCode.RightShift }
local adminWin = Nova.Window{ Title = "Admin", ToggleKey = Enum.KeyCode.F9, StartHidden = true }
```

### Programmatic Get / Set

```lua
local toggle = tab:AddToggle{ Text = "Mute", Default = false, Callback = function(v) print(v) end }
local slider = tab:AddSlider{ Text = "Vol",  Default = 50,    Callback = function(v) print(v) end }

print(toggle:Get())  --> false
toggle:Set(true)
slider:Set(80)
```

### Live Dropdown mutation

```lua
local dd = tab:AddDropdown{ Text = "Players", Options = {}, Callback = function(v) end }

game.ReplicatedStorage.PlayerList.OnClientEvent:Connect(function(list)
    dd:SetOptions(list)
end)
```

### Manual component registration

```lua
local comp = someTab:AddToggle{ Text = "X", Default = true, Callback = function(v) end }
Nova._cfg:Register("myExtraKey", comp, true)
```

### Player profile card

```lua
win:SetStatusText("Round 3 — 2 players left")
win:SetStatusText(nil)  -- reset to "NovaUI 1.4.0"
```

### Animating your own GUI

```lua
local frame = script.Parent.MyFrame

Nova.Animate(frame, "Size",             UDim2.fromOffset(300, 200), Nova.Presets.Bouncy)
Nova.Animate(frame, "BackgroundColor3", Color3.fromRGB(30, 30, 50), Nova.Presets.Smooth)
Nova.Snap(frame, "Size", UDim2.fromOffset(0, 0))
```

---

## Full Example

```lua
--!nonstrict
local Nova = require(game.ReplicatedStorage.NovaUI)

-- ── Window ────────────────────────────────────────────────────────────────────
local win = Nova.Window{
    Title     = "Nova Demo",
    Subtitle  = "v1.4",
    ToggleKey = Enum.KeyCode.RightShift,
    Size      = Vector2.new(600, 420),
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
    Increment = 10,
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
    Callback = function(v) game.Lighting.Brightness = v and 2 or 1 end,
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

-- ── Call AutoLoadConfig LAST, after all keyed components are defined ──────────
Nova.AutoLoadConfig()

-- ── Status line update ────────────────────────────────────────────────────────
task.delay(3, function()
    win:SetStatusText("Round started!")
end)
```

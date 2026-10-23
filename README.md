**NovaUI v1.0.0 — API Reference with Examples**

Licensed under the MIT License.

A modern, spring-animated UI library for Roblox (client-side) and Exploits. For Studio = Put the module in a `ModuleScript` named `NovaUI` (e.g. in `ReplicatedStorage`) and require it from a `LocalScript`:


```lua
local Nova = require(game:GetService("ReplicatedStorage"):WaitForChild("NovaUI"))
```

For Exploits = Put this at the top of your code, and use the variable exactly like the Roblox Studio version.

```lua
local Nova = loadstring(game:HttpGet("https://e"))()
```

All GUIs are created lazily and parented to `PlayerGui`; requiring the module draws nothing until you build something.

---

**Table of Contents:**

1. Constants & Module Fields
2. Theming
3. Spring Engine
4. Instance Factory — `Nova.ScreenGui`
5. Window
6. Container (Tab Pages) & Components
7. Notifications — `Nova.Notify`
8. Dialogs — `Nova.Dialog`
9. Error Handling
10. Performance & Internal Behavior

---

**1. Constants & Module Fields:**

| Field | Type | Value | Description |
|---|---|---|---|
| `Nova.Version` | string | `"1.0.0"` | Library version |
| `Nova.Theme` | table | see §2 | Live theme table |
| `Nova.Presets` | table | see §3 | Spring animation presets |
| `Nova.SetTheme` | function | — | Apply theme overrides |
| `Nova.Animate` | function | — | Spring-animate any supported property |
| `Nova.Snap` | function | — | Instant set, cancels springs |
| `Nova.ScreenGui` | function | — | ScreenGui factory |
| `Nova.Window` | function | — | Create a window |
| `Nova.Notify` | function | — | Show a toast notification |
| `Nova.Dialog` | function | — | Show a modal dialog |

**Example** — inspecting module fields:

```lua
print(Nova.Version)          --> "1.0.0"
print(Nova.Presets.Bouncy)   --> { 24, 0.55 }
print(Nova.Theme.Accent)     --> 124, 92, 255
```

---

**2. Theming:**

**`Nova.SetTheme(overrides)`** — iterates `overrides` and writes each key into the live theme table. **Call before building any UI**: colors and fonts are read once at element construction, so existing elements never retroactively re-theme.

| Key | Default | Consumed by |
|---|---|---|
| `Background` | `rgb(16,16,22)` | Window body, focused TextBox |
| `Surface` | `rgb(26,26,36)` | Top bar, cards, toasts, dialog card |
| `SurfaceHover` | `rgb(38,38,54)` | Hover fills, dropdown options |
| `Stroke` | `rgb(52,52,72)` | Strokes, tracks, dividers |
| `Accent` | `rgb(124,92,255)` | Indicator, active tabs, primary accents |
| `AccentAlt` | `rgb(64,170,255)` | Gradient second stop |
| `Text` | `rgb(240,240,250)` | Primary text, toggle knob |
| `SubText` | `rgb(145,145,170)` | Labels, placeholders, inactive tabs |
| `Success` | `rgb(70,210,140)` | `"success"` toasts |
| `Warning` | `rgb(255,190,70)` | Minimize hover, `"warning"` toasts |
| `Danger` | `rgb(255,90,105)` | Close hover, `"error"` toasts |
| `Font` | `Enum.Font.GothamMedium` | Default font (size 14) |
| `FontBold` | `Enum.Font.GothamBold` | Titles, emphasized labels |

**Example** — a pink/neon theme, set before building anything:

```lua
Nova.SetTheme({
    Accent = Color3.fromRGB(255, 80, 120),
    AccentAlt = Color3.fromRGB(255, 170, 80),
    Background = Color3.fromRGB(10, 10, 14),
    Surface = Color3.fromRGB(20, 20, 28),
    Font = Enum.Font.GothamMedium,
})

local win = Nova.Window{ Title = "Neon UI" } -- built with the new theme
```

**Example** — dark/light theme switch helper (rebuild your window after switching):

```lua
local themes = {
    dark = { Background = Color3.fromRGB(16, 16, 22), Text = Color3.fromRGB(240, 240, 250) },
    light = { Background = Color3.fromRGB(245, 245, 248), Text = Color3.fromRGB(30, 30, 40) },
}

local function applyTheme(name)
    Nova.SetTheme(themes[name])
end

applyTheme("light")
-- rebuild the window here so new elements pick up the theme
```

---

**3. Spring Engine:**

The engine integrates a damped harmonic oscillator per property, per frame. With position $p$, velocity $v$, target $t$, stiffness $k = \text{speed}^2$, and damping coefficient $c = 2 \cdot \text{damping} \cdot \text{speed}$, the update is:

$$v \mathrel{+}= (-k(p - t) - c\,v)\,h, \qquad p \mathrel{+}= v\,h$$

So `speed` (rad/s) is the undamped natural frequency — higher converges faster — and `damping` is the damping **ratio**: exactly `1` is critically damped (no overshoot), below `1` under-damped (bouncy), above `1` over-damped.

**Supported value types:**

| Type | Channels encoded |
|---|---|
| `number` | 1 |
| `Color3` | 3 (R, G, B) |
| `UDim` | 2 (Scale, Offset) |
| `UDim2` | 4 (X.Scale, X.Offset, Y.Scale, Y.Offset) |
| `Vector2` | 2 (X, Y) |

**`Nova.Animate(inst, prop, target, speed, damping)`** — springs `inst.prop` toward `target`. First call starts from the current value with zero velocity; interrupting an existing spring preserves position **and** velocity for smooth retargeting. `speed` may be a preset table, unpacked as `speed, damping`. Defaults: speed `22`, damping `0.9`.

**`Nova.Snap(inst, prop, value)`** — instantly sets the property and cancels any running spring on it.

**`Nova.Presets`:**

| Preset | speed | damping | Character |
|---|---|---|---|
| `Snappy` | 32 | 1 | Fast, zero overshoot |
| `Smooth` | 16 | 1 | Gentle, zero overshoot |
| `Bouncy` | 24 | 0.55 | Playful overshoot |
| `Wobbly` | 14 | 0.38 | Loose, exaggerated wobble |

**Example** — basic spring animation of a frame:

```lua
local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(100, 100)
frame.Position = UDim2.fromOffset(50, 50)
frame.BackgroundColor3 = Color3.new(1, 1, 1)
frame.Parent = Nova.ScreenGui("SpringDemo")

-- Bouncy slide using a preset table:
Nova.Animate(frame, "Position", UDim2.fromOffset(400, 200), Nova.Presets.Bouncy)

-- Raw numbers instead: speed 24, damping 0.6
Nova.Animate(frame, "Size", UDim2.fromOffset(200, 50), 24, 0.6)

-- Color transition with a snappy, no-overshoot feel:
Nova.Animate(frame, "BackgroundColor3", Color3.fromRGB(255, 80, 80), 32, 1)
```

**Example** — interruptible retargeting (move the target every frame; motion stays fluid):

```lua
local target = UDim2.fromOffset(100, 100)
Nova.Animate(frame, "Position", target, Nova.Presets.Bouncy)

task.wait(0.3) -- spring is mid-flight
target = UDim2.fromOffset(500, 300)
Nova.Animate(frame, "Position", target, Nova.Presets.Bouncy) -- continues smoothly from current pos+vel
```

**Example** — `Nova.Snap` to place something instantly (no animation):

```lua
Nova.Snap(frame, "Position", UDim2.fromOffset(50, 50)) -- teleports, cancels any spring
```

**Example** — a custom preset of your own:

```lua
local MY_PRESET = { 20, 0.7 } -- speed 20, mild bounce
Nova.Animate(frame, "Position", UDim2.fromOffset(200, 200), MY_PRESET)
```

---

**4. Instance Factory — `Nova.ScreenGui`:**

**`Nova.ScreenGui(name?, displayOrder?) → ScreenGui`**

Creates a ScreenGui in `PlayerGui` with `ResetOnSpawn = false`, `IgnoreGuiInset = true`, `ZIndexBehavior = Sibling`, `DisplayOrder` default 10.

**Example** — your own GUI, then spring-animate it:

```lua
local gui = Nova.ScreenGui("MyGui", 20)

local badge = Instance.new("TextLabel")
badge.Size = UDim2.fromOffset(120, 36)
badge.Position = UDim2.new(0.5, -60, 0, -50) -- off-screen above
badge.Text = "Level Up!"
badge.BackgroundColor3 = Color3.new(0, 0, 0)
badge.Parent = gui

-- Drop it in with a bounce:
Nova.Animate(badge, "Position", UDim2.new(0.5, -60, 0, 40), Nova.Presets.Bouncy)
```

---

**5. Window:**

**`Nova.Window(options) → Window`**

| Option | Type | Default | Description |
|---|---|---|---|
| `Title` | string | `"Nova UI"` | Top-bar title (rich text enabled) |
| `Subtitle` | string? | nil | Small `SubText`-colored text beside the title |
| `Size` | Vector2 | `(580, 400)` | Pixel size of the window root |
| `ToggleKey` | Enum.KeyCode? | nil | Open/close keybind; ignores keys consumed by other UI |
| `Gui` | ScreenGui? | nil | Parent into your own ScreenGui; `Destroy()` then removes only the window root |
| `Name` | string | `"NovaWindow"` | Name of the auto-created ScreenGui |
| `StartHidden` | boolean | false | Skip the automatic deferred `Open()` |

| Method | Signature | Behavior |
|---|---|---|
| `Open` | `win:Open()` | Fade + slide up + bouncy scale-in; no-op if open |
| `Close` | `win:Close()` | Fade out, slide down, scale 0.88; hides after 0.3s |
| `Toggle` | `win:Toggle()` | Open ↔ Close |
| `Minimize` | `win:Minimize(state?)` | Collapse to 46px top bar; toggle if no arg |
| `SetTitle` | `win:SetTitle(title, subtitle?)` | Update the rich-text title live |
| `SelectTab` | `win:SelectTab(tab)` | Activate a tab programmatically |
| `AddTab` | `win:AddTab(name, icon?)` | Add tab → returns **Container** |
| `Destroy` | `win:Destroy()` | Disconnect everything + destroy GUI |

**Example** — a full window with a keybind and subtitle:

```lua
local win = Nova.Window{
    Title = "Game Settings",
    Subtitle = "beta 0.3",
    Size = Vector2.new(560, 380),
    ToggleKey = Enum.KeyCode.RightShift, -- press RightShift to show/hide
}

local main = win:AddTab("Main", "🏠")
main:AddButton{ Text = "Hello!", Callback = function()
    print("clicked")
end }
```

**Example** — controlling the window from code:

```lua
local win = Nova.Window{ Title = "HUD", StartHidden = true }

win:SetTitle("HUD", "updated")     -- live title change
win:Open()                          -- show with animation
task.wait(3)
win:Minimize(true)                  -- collapse to just the top bar
task.wait(1)
win:Minimize(false)                 -- restore
task.wait(1)
win:Close()                         -- hide
task.wait(1)
win:Toggle()                        -- open again
```

**Example** — parenting into your own ScreenGui:

```lua
local gui = Nova.ScreenGui("MyHud", 50)
local win = Nova.Window{ Title = "Panel", Gui = gui }

win:Destroy() -- removes only the window root; "MyHud" survives
```

**Example** — jumping to a specific tab programmatically:

```lua
local a = win:AddTab("Stats", "📊")
local b = win:AddTab("Shop", "🛒")

task.wait(5)
win:SelectTab(b) -- same as the user clicking the Shop tab
```

---

**6. Container (Tab Pages) & Components:**

Each tab is a scrolling page. Components stack in creation order with 8px spacing. Card heights: Section 26 · Label auto · Button 40 · Toggle 44 · Slider 58 · TextInput 44 · Dropdown 44 (+expandable) · Progress 50.

**`tab:AddButton(options)`**

| Option | Type | Default |
|---|---|---|
| `Text` | string | `"Button"` |
| `Callback` | function? | nil |

Gradient button with a pointer-origin ripple; the gradient rotates to 110° on hover. Returns `{ Frame, SetText(_, text) }`.

**Example:**

```lua
local btn = tab:AddButton{ Text = "Respawn", Callback = function()
    Nova.Notify{ Title = "Respawning", Type = "info" }
end }

task.wait(2)
btn:SetText("Respawn Now") -- update the label later
```

**`tab:AddToggle(options)`**

| Option | Type | Default |
|---|---|---|
| `Text` | string | `"Toggle"` |
| `Default` | boolean | `false` |
| `Callback` | function?(newState: boolean) | nil |

Pill toggle with a squash-and-slide knob. Returns `{ Frame, Get(), Set(_, v) }`; `Set` fires the callback.

**Example:**

```lua
local music = tab:AddToggle{ Text = "Music", Default = true, Callback = function(on)
    print("Music:", on)
    -- sound.Volume = on and 1 or 0
end }

print(music:Get())       --> true
music:Set(false)         -- animates off and fires the callback
```

**`tab:AddSlider(options)`**

| Option | Type | Default |
|---|---|---|
| `Text` | string | `"Slider"` |
| `Min` | number | `0` |
| `Max` | number | `100` |
| `Default` | number | `Min` (clamped) |
| `Increment` | number | `1` — snapping step |
| `Suffix` | string | `""` — appended to the value label |
| `Callback` | function?(value: number) | nil |

Gradient-fill slider; the callback fires whenever the snapped value changes during a drag. Returns `{ Frame, Get(), Set(_, v) }`.

**Example:**

```lua
local volume = tab:AddSlider{
    Text = "Volume",
    Min = 0, Max = 100, Default = 50,
    Suffix = "%",
    Callback = function(v)
        sound.Volume = v / 100
    end,
}

-- Snap to a value from code (animates and fires the callback):
volume:Set(75)
```

**Example** — a 0.1-step float slider:

```lua
tab:AddSlider{
    Text = "Field of View",
    Min = 60, Max = 120, Default = 70,
    Increment = 0.1, Suffix = "°",
    Callback = function(v)
        workspace.CurrentCamera.FieldOfView = v
    end,
}
```

**`tab:AddTextInput(options)`**

| Option | Type | Default |
|---|---|---|
| `Text` | string | `"Input"` |
| `Default` | string | `""` — initial text |
| `Placeholder` | string | `""` |
| `Callback` | function?(text: string, enterPressed: boolean) | nil |

Text box that glows accent on focus; callback fires on focus loss with `(text, enterPressed)`. Returns `{ Frame, Get(), Set(_, t) }`.

**Example:**

```lua
tab:AddTextInput{
    Text = "Player name",
    Placeholder = "Type a name...",
    Callback = function(text, enterPressed)
        if enterPressed and text ~= "" then
            Nova.Notify{ Title = "Searching", Text = text }
        end
    end,
}
```

**Example** — reading/writing the box later:

```lua
local input = tab:AddTextInput{ Text = "Nickname", Default = "Player" }
print(input:Get())   --> "Player"
input:Set("Nova")    -- rewrite the text programmatically
```

**`tab:AddDropdown(options)`**

| Option | Type | Default |
|---|---|---|
| `Text` | string | `"Dropdown"` |
| `Options` | array | `{}` — any values, rendered via `tostring` |
| `Default` | any? | nil |
| `Callback` | function?(value) | nil |

Expanding dropdown (open height capped at 150px, scrollable). Returns `{ Frame, Get(), Set(_, v), SetOptions(_, newOptions) }`.

**Example:**

```lua
local mode = tab:AddDropdown{
    Text = "Difficulty",
    Options = { "Easy", "Normal", "Hard" },
    Default = "Normal",
    Callback = function(choice)
        print("Difficulty set to", choice)
    end,
}

print(mode:Get())          --> "Normal"
mode:Set("Hard")           -- select + fire callback (menu stays closed)

-- Swap the option list later (e.g. after loading a save):
mode:SetOptions({ "Story", "Nightmare" })
```

**Example** — dropdown of numbers (any value type works):

```lua
tab:AddDropdown{
    Text = "Render distance",
    Options = { 50, 100, 250, 500 },
    Default = 100,
    Callback = function(dist)
        settings():GetService("RenderSettings") -- hypothetical
    end,
}
```

**`tab:AddLabel(text)`** — auto-sizing wrapped text card. Returns `{ Frame, Set(_, t) }`.

**Example:**

```lua
local hint = tab:AddLabel("Drag the slider to adjust volume.")

task.wait(3)
hint:Set("All changes save automatically.") -- swap the text later
```

**`tab:AddSection(text)`** — uppercase accent section header (26px). Returns `{ Frame }`.

**Example:**

```lua
tab:AddSection("Audio")
tab:AddToggle{ Text = "Music" }
tab:AddSlider{ Text = "Volume" }

tab:AddSection("Graphics")
tab:AddToggle{ Text = "Shadows" }
```

**`tab:AddProgress(options)`**

| Option | Type | Default |
|---|---|---|
| `Text` | string | `"Progress"` |
| `Value` | number (0–1) | `0` |

Progress bar with a percentage label. Returns `{ Frame, Set(_, fraction) }`; `Set` springs the fill and updates the label, no callback.

**Example** — a fake loading sequence:

```lua
local progress = tab:AddProgress{ Text = "Loading assets", Value = 0 }

task.spawn(function()
    for i = 1, 10 do
        task.wait(0.4)
        progress:Set(i / 10) -- springs to 10%, 20%, ... 100%
    end
    Nova.Notify{ Title = "Loaded", Type = "success" }
end)
```

**Example** — wiring components together (full tab):

```lua
local settings = win:AddTab("Settings", "⚙️")

settings:AddSection("Audio")
local sfx = settings:AddToggle{ Text = "Sound effects", Default = true }
local vol = settings:AddSlider{ Text = "Volume", Min = 0, Max = 100, Default = 80, Suffix = "%" }

settings:AddSection("Profile")
settings:AddTextInput{ Text = "Display name", Default = "Player" }
settings:AddDropdown{ Text = "Region", Options = { "NA", "EU", "ASIA" }, Default = "NA" }
settings:AddLabel("Changes apply immediately and are saved per device.")

settings:AddButton{ Text = "Reset to defaults", Callback = function()
    sfx:Set(true)
    vol:Set(80)
    Nova.Notify{ Title = "Defaults restored", Type = "success", Duration = 3 }
end }
```

---

**7. Notifications — `Nova.Notify`:**

**`Nova.Notify(options) → { Dismiss: function }`**

Toasts stack bottom-right (DisplayOrder 1000 overlay, created lazily and reused).

| Option | Type | Default | Description |
|---|---|---|---|
| `Title` | string | `"Notification"` | Bold size-14 header |
| `Text` | string | `""` | Wrapped, end-truncated body |
| `Type` | string | `"info"` | `"info"` · `"success"` · `"warning"` · `"error"` (unknown falls back to `info`) |
| `Duration` | number | `4` | Seconds until auto-dismiss |

Timer bar depletes linearly; clicking the toast dismisses early. `Dismiss()` is idempotent.

**Example** — each toast type:

```lua
Nova.Notify{ Title = "Info", Text = "Update available.", Type = "info" }
Nova.Notify{ Title = "Saved", Text = "Settings stored.", Type = "success", Duration = 3 }
Nova.Notify{ Title = "Low memory", Text = "Consider restarting.", Type = "warning" }
Nova.Notify{ Title = "Failed", Text = "Could not connect to server.", Type = "error" }
```

**Example** — dismissing programmatically:

```lua
local t = Nova.Notify{ Title = "Uploading", Text = "Please wait...", Duration = 30 }
task.wait(2)
t.Dismiss() -- slide out early
```

**Example** — using a toast as a temporary status inside a callback:

```lua
tab:AddButton{ Text = "Teleport to spawn", Callback = function()
    local t = Nova.Notify{ Title = "Teleporting...", Type = "info" }
    character:PivotTo(workspace.SpawnLocation.CFrame)
    task.wait(0.5)
    t.Dismiss()
    Nova.Notify{ Title = "Arrived", Type = "success", Duration = 2 }
end }
```

---

**8. Dialogs — `Nova.Dialog`:**

**`Nova.Dialog(options) → { Close: function }`**

Centered modal (DisplayOrder 900) with a 45%-black backdrop; the 340px card auto-sizes to content. Button callbacks fire after the close animation.

| Option | Type | Default | Description |
|---|---|---|---|
| `Title` | string | `"Dialog"` | Bold size-18 header |
| `Text` | string | `""` | Wrapped body |
| `Buttons` | array? | `{ {Text="OK", Primary=true} }` | Each: `{ Text?, Primary?, Callback? }` |
| `Dismissible` | boolean | `true` | Backdrop click closes |

`Close()` runs the close animation but fires **no** button callback. All close paths are guarded against double-firing.

**Example** — a confirm/cancel dialog:

```lua
Nova.Dialog{
    Title = "Delete save?",
    Text = "This cannot be undone.",
    Buttons = {
        { Text = "Cancel" },
        { Text = "Delete", Primary = true, Callback = function()
            Nova.Notify{ Title = "Deleted", Type = "error", Duration = 3 }
        end },
    },
}
```

**Example** — a forced (non-dismissible) modal:

```lua
Nova.Dialog{
    Title = "Update required",
    Text = "Please rejoin to download version 1.1.",
    Dismissible = false, -- backdrop click does nothing
    Buttons = {
        { Text = "Rejoin", Primary = true, Callback = function()
            -- TeleportService:Teleport(game.PlaceId)
        end },
    },
}
```

**Example** — three buttons and programmatic close:

```lua
local dlg = Nova.Dialog{
    Title = "Unsaved changes",
    Text = "Do you want to save before quitting?",
    Buttons = {
        { Text = "Discard", Callback = function() quit() end },
        { Text = "Save", Primary = true, Callback = function() save(); quit() end },
    },
}
task.delay(30, function()
    dlg.Close() -- auto-close after 30s; fires no button callback
end)
```

---

**9. Error Handling:**

- `Nova.Animate` raises `"NovaUI: cannot animate value of type <type>"` for unsupported target types.

```lua
-- WRONG: errors — CFrame is not supported
-- Nova.Animate(part, "CFrame", CFrame.new(0, 10, 0), 24, 0.6)

-- RIGHT: animate supported GUI properties only
Nova.Animate(frame, "Position", UDim2.fromOffset(0, 10), 24, 0.6)
```

- Animating a property that doesn't exist on the instance errors at the Roblox property-assignment level — e.g. `GroupTransparency` only exists on `CanvasGroup` / `ImageLabel`-style grouped frames.
- `Nova.Notify` with an unknown `Type` string falls back to `info` color rather than erroring.
- Unknown keys in any options table are silently ignored.

---

**10. Performance & Internal Behavior:**

- **Single driver loop.** One shared `RenderStepped` connection steps *all* springs and self-disconnects once everything settles (`|p − t| ≤ 0.001`, `|v| ≤ 0.01`).
- **Stability.** Frame `dt` is clamped to 0.05s and sub-stepped at up to 240Hz, so springs survive hitches and low framerates.
- **No leaks.** Instances are weakly tracked with a `Destroying:Once` hook; spring state clears automatically. Windows pool their connections for one-shot cleanup in `Destroy`.
- **Callback safety.** All user callbacks run via `task.spawn` — yielding inside them never blocks UI events.
- **Touch-friendly.** Press detection accepts `MouseButton1` and `Touch`; dragging (window and sliders) continues outside the control via global `InputChanged`/`InputEnded`.
- **Z-index layering.** Windows (10) < dialogs (900) < toasts (1000); within cards, hit areas sit at `ZIndex 5` above content at 3 and ripples at 2.

**Example** — putting it all together in a complete working script:

```lua
-- LocalScript in StarterPlayerScripts
local Nova = require(game:GetService("ReplicatedStorage"):WaitForChild("NovaUI"))

Nova.SetTheme({ Accent = Color3.fromRGB(124, 92, 255) })

local win = Nova.Window{
    Title = "Demo Hub",
    Subtitle = "NovaUI v1.0",
    ToggleKey = Enum.KeyCode.RightShift,
}

local home = win:AddTab("Home", "🏠")
home:AddSection("Welcome")
home:AddLabel("Press RightShift to toggle this window at any time.")
local bar = home:AddProgress{ Text = "Session progress", Value = 0 }

local audio = win:AddTab("Audio", "🔊")
local soundOn = audio:AddToggle{ Text = "Sound", Default = true, Callback = function(on)
    Nova.Notify{ Title = on and "Sound on" or "Sound off", Type = on and "success" or "warning", Duration = 2 }
end }
audio:AddSlider{ Text = "Volume", Min = 0, Max = 100, Default = 50, Suffix = "%", Callback = function(v)
    bar:Set(v / 100)
end }

home:AddButton{ Text = "Open confirm dialog", Callback = function()
    Nova.Dialog{
        Title = "Reset settings?",
        Text = "All toggles and sliders return to their defaults.",
        Buttons = {
            { Text = "Cancel" },
            { Text = "Reset", Primary = true, Callback = function()
                soundOn:Set(true)
                Nova.Notify{ Title = "Reset complete", Type = "success" }
            end },
        },
    }
end }
```

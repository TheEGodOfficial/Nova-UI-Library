--!nonstrict
--[[
	NovaUI v1.4 | modern, spring-animated UI library for Roblox (client-side)

	Install: put this in a ModuleScript named "NovaUI" (ReplicatedStorage works well)
	and require it from a LocalScript.

	Features
	  * Spring physics engine (interruptible, bouncy, no tween snapping)
	  * Window: draggable, minimize, open/close animations, rotating gradient border,
	    animated tab sidebar, staggered content reveal, toggle keybind
	  * Components: Button (ripple), Toggle, Slider, TextInput, Dropdown,
	    MultiDropdown, ColorPicker, Keybind, Label, Section, ProgressBar
	  * Toast notifications (slide, stack, timer bar) and animated Dialogs
	  * Themeable and mobile-aware (auto-fit scale)

	Quick API
	  local win = Nova.Window{ Title = "My Game", Subtitle = "v1", ToggleKey = Enum.KeyCode.RightShift }
	  local tab = win:AddTab("Main", "🏠")
	  tab:AddButton{ Text = "Hi", Callback = function() end }
	  tab:AddToggle{ Text = "Sound", Default = true, Callback = function(v) end }
	  tab:AddSlider{ Text = "Volume", Min = 0, Max = 100, Default = 50, Callback = function(v) end }
	  tab:AddTextInput{ Text = "Name", Placeholder = "Type...", Callback = function(text, enter) end }
	  tab:AddDropdown{ Text = "Mode", Options = {"A","B"}, Default = "A", Callback = function(v) end }
	  tab:AddMultiDropdown{ Text = "Flags", Options = {"A","B","C"}, Default = {"A"}, Callback = function(tbl) end }
	  tab:AddColorPicker{ Text = "Color", Default = Color3.fromRGB(255,80,120), Callback = function(c) end }
	  tab:AddKeybind{ Text = "Sprint", Default = Enum.KeyCode.LeftShift, Callback = function(key) end }
	  tab:AddLabel("Some text") ; tab:AddSection("Header") ; tab:AddProgress{ Text = "XP", Value = 0.4 }
	  Nova.Notify{ Title = "Saved", Text = "Done!", Type = "success", Duration = 4 }
	  Nova.Dialog{ Title = "Sure?", Text = "...", Buttons = { { Text = "Yes", Primary = true } } }
	  Nova.Animate(anyGuiObject, "Size", UDim2.fromOffset(200, 50), 24, 0.6) -- spring anything

	Dropdown live-update:
	  local dd = tab:AddDropdown{ ... }
	  dd:AddOption("NewItem")          -- adds without closing
	  dd:RemoveOption("OldItem")       -- removes and deselects if it was selected
	  dd:SetOptions({ "X","Y","Z" })   -- full replace (existing API)

	TextInput Set now fires Callback with enter=true:
	  input:Set("hello")  -- fires Callback("hello", true)

	v1.4 additions
	  * Tab names that are too wide truncate with "…" and show a tooltip on hover
	  * ScreenGui parenting: gethui() → CoreGui → PlayerGui (automatic fallback)
	  * Keybind picker added to the Theme tab for the window open/close toggle
	  * Player profile card at the sidebar bottom: avatar, display name (tooltip shows
	    username + UserId), and a customisable status line via win:SetStatusText("text")

	Config system (multi-profile, game/global scope, selector, auto-load):
	  -- Tag components with Key = "..." anywhere BEFORE calling MountConfig:
	  tab:AddToggle{ Text = "God Mode", Key = "godMode", Default = false, Callback = ... }
	  tab:AddSlider{ Text = "Speed",    Key = "speed",   Default = 16,    Callback = ... }
	  -- Then mount the config UI onto a dedicated tab:
	  local cfgTab = win:AddTab("Config", "⚙️")
	  cfgTab:MountConfig()
	  -- The GUI provides a Game/Global scope toggle, profile selector,
	  -- name input, Save New, Overwrite, Load, Delete, Reset Defaults buttons,
	  -- and auto-loads the last used profile on startup.
	  -- Manual register (optional): Nova._cfg:Register("key", component)

	Theme system (live color pickers, built-in presets, named theme profiles):
	  local themeTab = win:AddTab("Theme", "🎨")
	  themeTab:MountTheme()
	  -- The GUI provides a Game/Global scope toggle, built-in preset buttons
	  -- (Nova Dark, Midnight, Crimson, Ocean, Forest, Mono), live color pickers
	  -- per Theme key, a keybind picker for the window toggle, a theme profile
	  -- selector, Save New, Overwrite, Load, Delete; auto-loads last used theme.
	  -- All color changes apply to Nova.Theme instantly (live UI update).

	Player profile card (auto-populated in the sidebar):
	  win:SetStatusText("Playing ranked match")  -- change the bottom status line
	  win:SetStatusText(nil)                      -- resets to "NovaUI 1.4.0"
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local Nova = {}
Nova.Version = "1.4.0"

--------------------------------------------------------------------------------
-- Theme
--------------------------------------------------------------------------------

Nova.Theme = {
	Background  = Color3.fromRGB(16, 16, 22),
	Surface     = Color3.fromRGB(26, 26, 36),
	SurfaceHover= Color3.fromRGB(38, 38, 54),
	Stroke      = Color3.fromRGB(52, 52, 72),
	Accent      = Color3.fromRGB(124, 92, 255),
	AccentAlt   = Color3.fromRGB(64, 170, 255),
	Text        = Color3.fromRGB(240, 240, 250),
	SubText     = Color3.fromRGB(145, 145, 170),
	Success     = Color3.fromRGB(70, 210, 140),
	Warning     = Color3.fromRGB(255, 190, 70),
	Danger      = Color3.fromRGB(255, 90, 105),
	Font        = Enum.Font.GothamMedium,
	FontBold    = Enum.Font.GothamBold,
}
local Theme = Nova.Theme

function Nova.SetTheme(overrides)
	for k, v in overrides do Theme[k] = v end
end

--------------------------------------------------------------------------------
-- Spring engine
--------------------------------------------------------------------------------

local P = {
	Snappy = { 32, 1 },
	Smooth = { 16, 1 },
	Bouncy = { 24, 0.55 },
	Wobbly = { 14, 0.38 },
}
Nova.Presets = P

local Springs = {}
local Tracked  = setmetatable({}, { __mode = "k" })
local stepConn

local function encode(v)
	local t = typeof(v)
	if t == "number"  then return { v } end
	if t == "Color3"  then return { v.R, v.G, v.B } end
	if t == "UDim2"   then return { v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset } end
	if t == "Vector2" then return { v.X, v.Y } end
	if t == "UDim"    then return { v.Scale, v.Offset } end
	error("NovaUI: cannot animate value of type " .. t)
end

local function decode(kind, a, prop)
	if kind == "number"  then
		if string.find(prop, "Transparency") then return math.clamp(a[1], 0, 1) end
		return a[1]
	end
	if kind == "Color3"  then return Color3.new(math.clamp(a[1],0,1), math.clamp(a[2],0,1), math.clamp(a[3],0,1)) end
	if kind == "UDim2"   then return UDim2.new(a[1], a[2], a[3], a[4]) end
	if kind == "Vector2" then return Vector2.new(a[1], a[2]) end
	if kind == "UDim"    then return UDim.new(a[1], a[2]) end
end

local function stepAll(dt)
	dt = math.min(dt, 0.05)
	local sub = math.max(1, math.ceil(dt * 240))
	local h = dt / sub

	for inst, props in Springs do
		for prop, s in props do
			local pos, vel, tgt = s.pos, s.vel, s.tgt
			local k = s.speed * s.speed
			local c = 2 * s.damping * s.speed
			local settled = true
			for i = 1, #pos do
				local p, v, t = pos[i], vel[i], tgt[i]
				for _ = 1, sub do
					v += (-k * (p - t) - c * v) * h
					p += v * h
				end
				if math.abs(p - t) > 0.001 or math.abs(v) > 0.01 then settled = false end
				pos[i], vel[i] = p, v
			end
			if settled then
				for i = 1, #pos do pos[i], vel[i] = tgt[i], 0 end
				props[prop] = nil
			end
			inst[prop] = decode(s.kind, pos, prop)
		end
		if next(props) == nil then Springs[inst] = nil end
	end

	if next(Springs) == nil and stepConn then
		stepConn:Disconnect()
		stepConn = nil
	end
end

function Nova.Animate(inst, prop, target, speed, damping)
	if type(speed) == "table" then speed, damping = speed[1], speed[2] end
	local kind  = typeof(target)
	local props = Springs[inst]
	if not props then
		props = {}
		Springs[inst] = props
		if not Tracked[inst] then
			Tracked[inst] = true
			inst.Destroying:Once(function() Springs[inst] = nil end)
		end
	end
	local tgt = encode(target)
	local s   = props[prop]
	if s and s.kind == kind then
		s.tgt    = tgt
		s.speed  = speed  or s.speed
		s.damping= damping or s.damping
	else
		local cur = encode(inst[prop])
		props[prop] = { kind = kind, pos = cur, vel = table.create(#cur, 0),
		                tgt = tgt, speed = speed or 22, damping = damping or 0.9 }
	end
	if not stepConn then
		stepConn = RunService.RenderStepped:Connect(stepAll)
	end
end

function Nova.Snap(inst, prop, value)
	local props = Springs[inst]
	if props then props[prop] = nil end
	inst[prop] = value
end

local function A(inst, prop, target, preset)
	preset = preset or P.Smooth
	Nova.Animate(inst, prop, target, preset[1], preset[2])
end

local function put(inst, prop, value, preset, instant)
	if instant then Nova.Snap(inst, prop, value) else A(inst, prop, value, preset) end
end

--------------------------------------------------------------------------------
-- Instance helpers
--------------------------------------------------------------------------------

local function create(class, props, children)
	local inst = Instance.new(class)
	if inst:IsA("GuiObject") then
		inst.BorderSizePixel = 0
		inst.BackgroundTransparency = 1
	end
	if inst:IsA("GuiButton") then inst.AutoButtonColor = false end
	if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
		inst.Text        = ""
		inst.Font        = Theme.Font
		inst.TextColor3  = Theme.Text
		inst.TextSize    = 14
	end
	if props then
		if props.BackgroundColor3 and props.BackgroundTransparency == nil then
			inst.BackgroundTransparency = 0
		end
		for k, v in props do
			if k ~= "Parent" then inst[k] = v end
		end
	end
	if children then
		for _, c in children do c.Parent = inst end
	end
	if props and props.Parent then inst.Parent = props.Parent end
	return inst
end

local function corner(r)
	return create("UICorner", { CornerRadius = UDim.new(0, r) })
end
local function pill()
	return create("UICorner", { CornerRadius = UDim.new(1, 0) })
end
local function stroke(color, thickness, transparency)
	return create("UIStroke", {
		Color = color, Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end
local function padding(l, t, r, b)
	return create("UIPadding", {
		PaddingLeft   = UDim.new(0, l), PaddingTop    = UDim.new(0, t),
		PaddingRight  = UDim.new(0, r), PaddingBottom = UDim.new(0, b),
	})
end
local function rgbString(c)
	return string.format("rgb(%d,%d,%d)",
		math.floor(c.R*255+0.5), math.floor(c.G*255+0.5), math.floor(c.B*255+0.5))
end
local function fmt(v)
	return tostring(math.round(v * 1000) / 1000)
end
local function isPress(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
	    or input.UserInputType == Enum.UserInputType.Touch
end

local function hoverable(btn, target, scaleObj, normalColor, hoverColor, hoverScale)
	hoverScale = hoverScale or 1.02
	btn.MouseEnter:Connect(function()
		if hoverColor then A(target, "BackgroundColor3", hoverColor, P.Snappy) end
		A(scaleObj, "Scale", hoverScale, P.Bouncy)
	end)
	btn.MouseLeave:Connect(function()
		if normalColor then A(target, "BackgroundColor3", normalColor, P.Snappy) end
		A(scaleObj, "Scale", 1, P.Snappy)
	end)
	btn.MouseButton1Down:Connect(function() A(scaleObj, "Scale", 0.96, P.Snappy) end)
	btn.MouseButton1Up:Connect(function()   A(scaleObj, "Scale", hoverScale, P.Bouncy) end)
end

local function ripple(face, input)
	local point = Vector2.new(input.Position.X, input.Position.Y) + GuiService:GetGuiInset()
	local rel   = (point - face.AbsolutePosition) / face.AbsoluteSize
	local r = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position    = UDim2.fromScale(math.clamp(rel.X, 0, 1), math.clamp(rel.Y, 0, 1)),
		Size        = UDim2.fromScale(0, 0),
		SizeConstraint = Enum.SizeConstraint.RelativeXX,
		BackgroundColor3    = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.72,
		ZIndex      = 4,   -- above label (ZIndex 3) but below hit (ZIndex 5)
		Parent      = face,
	}, { pill() })
	A(r, "Size", UDim2.fromScale(2.6, 2.6), { 12, 1 })
	A(r, "BackgroundTransparency", 1, { 9, 1 })
	task.delay(0.8, function() r:Destroy() end)
end

-- Colour helpers
local function hsvToRgb(h, s, v)
	if s == 0 then return Color3.new(v, v, v) end
	h = h * 6
	local i = math.floor(h)
	local f = h - i
	local p = v * (1 - s)
	local q = v * (1 - s * f)
	local t = v * (1 - s * (1 - f))
	local r, g, b
	i = i % 6
	if     i == 0 then r,g,b = v,t,p
	elseif i == 1 then r,g,b = q,v,p
	elseif i == 2 then r,g,b = p,v,t
	elseif i == 3 then r,g,b = p,q,v
	elseif i == 4 then r,g,b = t,p,v
	elseif i == 5 then r,g,b = v,p,q
	end
	return Color3.new(r, g, b)
end

local function rgbToHsv(c)
	local r, g, b = c.R, c.G, c.B
	local max = math.max(r, g, b)
	local min = math.min(r, g, b)
	local d   = max - min
	local h, s, v = 0, (max == 0 and 0 or d/max), max
	if d ~= 0 then
		if     max == r then h = (g - b) / d % 6
		elseif max == g then h = (b - r) / d + 2
		else                 h = (r - g) / d + 4
		end
		h = h / 6
	end
	return h, s, v
end

local function colorToHex(c)
	return string.format("%02X%02X%02X",
		math.floor(c.R*255+0.5), math.floor(c.G*255+0.5), math.floor(c.B*255+0.5))
end

local function hexToColor(hex)
	hex = hex:gsub("^#", "")
	if #hex ~= 6 then return nil end
	local r = tonumber(hex:sub(1,2), 16)
	local g = tonumber(hex:sub(3,4), 16)
	local b = tonumber(hex:sub(5,6), 16)
	if not (r and g and b) then return nil end
	return Color3.fromRGB(r, g, b)
end

local function keyName(key)
	if key == Enum.KeyCode.Unknown then return "None" end
	local n = key.Name
	-- strip leading "Left"/"Right" prefix for display neatness
	return n
end

--------------------------------------------------------------------------------
-- ScreenGui factory
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Tooltip helper (reused for tab labels and player card)
--------------------------------------------------------------------------------

local tooltipGui   -- lazily created ScreenGui
local tooltipFrame
local tooltipLabel

local function ensureTooltip()
	if tooltipFrame and tooltipFrame.Parent then return end
	tooltipGui   = Nova.ScreenGui("NovaTooltip", 1100)
	tooltipFrame = create("Frame", {
		Size             = UDim2.fromOffset(0, 0),
		AutomaticSize    = Enum.AutomaticSize.XY,
		BackgroundColor3 = Theme.Surface,
		Visible          = false,
		ZIndex           = 99,
		Parent           = tooltipGui,
	}, { corner(6), stroke(Theme.Stroke, 1, 0.3), padding(10, 5, 10, 5) })
	tooltipLabel = create("TextLabel", {
		Size           = UDim2.fromOffset(0, 0),
		AutomaticSize  = Enum.AutomaticSize.XY,
		Text           = "",
		TextSize       = 12,
		TextColor3     = Theme.SubText,
		TextWrapped    = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex         = 99,
		Parent         = tooltipFrame,
	})
end

local tooltipConn
local function showTooltip(text)
	ensureTooltip()
	tooltipLabel.Text    = text
	tooltipFrame.Visible = true
	if tooltipConn then tooltipConn:Disconnect() end
	tooltipConn = RunService.RenderStepped:Connect(function()
		if not tooltipFrame or not tooltipFrame.Parent then
			tooltipConn:Disconnect(); return
		end
		local mp = UserInputService:GetMouseLocation()
		tooltipFrame.Position = UDim2.fromOffset(mp.X + 14, mp.Y + 6)
	end)
end

local function hideTooltip()
	if tooltipFrame then tooltipFrame.Visible = false end
	if tooltipConn  then tooltipConn:Disconnect(); tooltipConn = nil end
end

-- Wire a GuiObject to show a tooltip on hover.
-- truncateLabel: optional TextLabel to set TextTruncate + ElideText behaviour
local function withTooltip(hoverObject, text)
	hoverObject.MouseEnter:Connect(function() showTooltip(text) end)
	hoverObject.MouseLeave:Connect(hideTooltip)
end

--------------------------------------------------------------------------------
-- ScreenGui factory
--------------------------------------------------------------------------------

function Nova.ScreenGui(name, displayOrder)
	-- Parent priority: gethui() → CoreGui → PlayerGui
	local parent
	if type(gethui) == "function" then
		local ok, h = pcall(gethui)
		if ok and h then parent = h end
	end
	if not parent then
		local ok, cg = pcall(function() return game:GetService("CoreGui") end)
		if ok and cg then
			local test = pcall(function()
				local s = Instance.new("ScreenGui"); s.Parent = cg; s:Destroy()
			end)
			if test then parent = cg end
		end
	end
	if not parent then
		parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	end
	return create("ScreenGui", {
		Name            = name or "NovaUI",
		ResetOnSpawn    = false,
		IgnoreGuiInset  = true,
		ZIndexBehavior  = Enum.ZIndexBehavior.Sibling,
		DisplayOrder    = displayOrder or 10,
		Parent          = parent,
	})
end

--------------------------------------------------------------------------------
-- Container (a tab page). Holds all the Add* component methods.
--------------------------------------------------------------------------------

local Container = {}
Container.__index = Container

local function newContainer(window, scroll)
	return setmetatable({ Window = window, Scroll = scroll, Cards = {}, _order = 0 }, Container)
end

function Container:_card(height, bare)
	self._order += 1
	local card = create("Frame", {
		Size            = UDim2.new(1, 0, 0, height),
		LayoutOrder     = self._order,
		BackgroundColor3= if bare then nil else Theme.Surface,
		Parent          = self.Scroll,
	})
	if not bare then
		corner(8).Parent = card
		stroke(Theme.Stroke, 1, 0.4).Parent = card
	end
	local scale = create("UIScale", { Parent = card })
	table.insert(self.Cards, scale)
	return card, scale
end

local function cardHover(card, hit, scale)
	hit.MouseEnter:Connect(function()
		A(card,  "BackgroundColor3", Theme.SurfaceHover, P.Snappy)
		A(scale, "Scale",            1.01,               P.Bouncy)
	end)
	hit.MouseLeave:Connect(function()
		A(card,  "BackgroundColor3", Theme.Surface, P.Snappy)
		A(scale, "Scale",            1,             P.Snappy)
	end)
end

function Container:AddSection(text)
	local card = self:_card(26, true)
	create("TextLabel", {
		Size             = UDim2.fromScale(1, 1),
		Text             = string.upper(text or "Section"),
		Font             = Theme.FontBold,
		TextSize         = 11,
		TextColor3       = Theme.Accent,
		TextXAlignment   = Enum.TextXAlignment.Left,
		TextYAlignment   = Enum.TextYAlignment.Bottom,
		Parent           = card,
	}, { padding(4, 0, 0, 2) })
	return { Frame = card }
end

function Container:AddLabel(text)
	local card = self:_card(0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	padding(14, 11, 14, 11).Parent = card
	local lbl = create("TextLabel", {
		Size           = UDim2.new(1, 0, 0, 0),
		AutomaticSize  = Enum.AutomaticSize.Y,
		Text           = text or "",
		TextColor3     = Theme.SubText,
		TextWrapped    = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent         = card,
	})
	return {
		Frame = card,
		Set   = function(_, t) lbl.Text = t end,
	}
end

-- ── Button ──────────────────────────────────────────────────────────────────
-- Fix: label lives inside `face` (CanvasGroup) at ZIndex 3.
-- Ripple is now spawned at ZIndex 4, so it draws OVER the label briefly,
-- which looks correct. The transparent hit button is at ZIndex 5 on `card`
-- (parent of face), so it captures input but never obscures anything inside face.
function Container:AddButton(o)
	o = o or {}
	local card, scale = self:_card(40, true)

	local grad = create("UIGradient", {
		Color    = ColorSequence.new(Theme.Accent, Theme.AccentAlt),
		Rotation = 20,
	})
	-- face is a CanvasGroup so ripple clips to rounded corners
	local face = create("Frame", {
    	Size             = UDim2.fromScale(1, 1),
    	BackgroundColor3 = Color3.new(1, 1, 1),
    	Parent           = card,
	}, { corner(8), grad })

	local label = create("TextLabel", {
		Size           = UDim2.fromScale(1, 1),
		Text           = o.Text or "Button",
		Font           = Theme.FontBold,
		TextColor3     = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		ZIndex         = 3,
		Parent         = face,
	})

	-- hit sits on card (same level as face) so it captures the full card area
	-- ZIndex 5 puts it above face's children visually but input still routes through
	local hit = create("TextButton", {
    	Size   = UDim2.fromScale(1, 1),
    	ZIndex = 5,
    	Parent = face,  -- ← inside face, not card
	})

	hit.MouseEnter:Connect(function()
		A(scale, "Scale",   1.02, P.Bouncy)
		A(grad,  "Rotation", 110, { 10, 1 })
	end)
	hit.MouseLeave:Connect(function()
		A(scale, "Scale",    1,  P.Snappy)
		A(grad,  "Rotation", 20, { 10, 1 })
	end)
	hit.MouseButton1Down:Connect(function() A(scale, "Scale", 0.96, P.Snappy) end)
	hit.MouseButton1Up:Connect(function()   A(scale, "Scale", 1.02, P.Bouncy) end)
	hit.InputBegan:Connect(function(input)
		if isPress(input) then ripple(face, input) end
	end)
	hit.Activated:Connect(function()
		if o.Callback then task.spawn(o.Callback) end
	end)

	return {
		Frame   = card,
		SetText = function(_, t) label.Text = t end,
	}
end

-- ── Toggle ───────────────────────────────────────────────────────────────────
function Container:AddToggle(o)
	o = o or {}
	local card, scale = self:_card(44)
	create("TextLabel", {
		Position = UDim2.fromOffset(14, 0),
		Size     = UDim2.new(1, -80, 1, 0),
		Text     = o.Text or "Toggle",
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent   = card,
	})
	local track = create("Frame", {
		AnchorPoint      = Vector2.new(1, 0.5),
		Position         = UDim2.new(1, -14, 0.5, 0),
		Size             = UDim2.fromOffset(44, 24),
		BackgroundColor3 = Theme.Stroke,
		Parent           = card,
	}, { pill() })
	local knob = create("Frame", {
		AnchorPoint      = Vector2.new(0, 0.5),
		Position         = UDim2.new(0, 3, 0.5, 0),
		Size             = UDim2.fromOffset(18, 18),
		BackgroundColor3 = Theme.Text,
		Parent           = track,
	}, { pill() })
	local hit = create("TextButton", { Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = card })

	local state   = o.Default == true
	local pressed = false

	local function render(instant)
		local w = pressed and 24 or 18
		local x = state and (44 - 3 - w) or 3
		put(knob,  "Size",             UDim2.fromOffset(w, 18),      P.Snappy, instant)
		put(knob,  "Position",         UDim2.new(0, x, 0.5, 0),      P.Bouncy, instant)
		put(track, "BackgroundColor3", state and Theme.Accent or Theme.Stroke, P.Snappy, instant)
	end
	render(true)

	local function set(v, fire)
		state = v
		render(false)
		if fire and o.Callback then task.spawn(o.Callback, state) end
	end

	cardHover(card, hit, scale)
	hit.MouseButton1Down:Connect(function() pressed = true;  render(false) end)
	local function release()
		if pressed then pressed = false; render(false) end
	end
	hit.MouseButton1Up:Connect(release)
	hit.MouseLeave:Connect(release)
	hit.Activated:Connect(function() set(not state, true) end)

	return {
		Frame = card,
		Get   = function()    return state end,
		Set   = function(_, v) set(v == true, true) end,
	}
end

-- ── Slider ───────────────────────────────────────────────────────────────────
function Container:AddSlider(o)
	o = o or {}
	local min, max, inc = o.Min or 0, o.Max or 100, o.Increment or 1
	local suffix = o.Suffix or ""
	local value  = math.clamp(o.Default or min, min, max)
	local card, scale = self:_card(58)

	create("TextLabel", {
		Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -100, 0, 18),
		Text = o.Text or "Slider", TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	local valueLabel = create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position    = UDim2.new(1, -14, 0, 8), Size = UDim2.fromOffset(80, 18),
		Font = Theme.FontBold, TextColor3 = Theme.Accent,
		TextXAlignment = Enum.TextXAlignment.Right, Parent = card,
	})
	local track = create("Frame", {
		Position = UDim2.new(0, 14, 0, 38), Size = UDim2.new(1, -28, 0, 6),
		BackgroundColor3 = Theme.Stroke, Parent = card,
	}, { pill() })
	local fill = create("Frame", {
		Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = track,
	}, { pill(), create("UIGradient", { Color = ColorSequence.new(Theme.Accent, Theme.AccentAlt) }) })
	local knob = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(14, 14), BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 3, Parent = fill,
	}, { pill(), stroke(Theme.Accent, 2, 0) })
	local hit = create("TextButton", {
		Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 36),
		ZIndex = 5, Parent = card,
	})

	local last = nil
	local function setValue(v, fire)
		v = min + math.floor((v - min) / inc + 0.5) * inc
		v = math.clamp(v, min, max)
		value = v
		A(fill, "Size", UDim2.new((v - min) / (max - min), 0, 1, 0), { 34, 1 })
		valueLabel.Text = fmt(v) .. suffix
		if fire and v ~= last then
			last = v
			if o.Callback then task.spawn(o.Callback, v) end
		end
	end
	setValue(value, false)
	Nova.Snap(fill, "Size", UDim2.new((value - min) / (max - min), 0, 1, 0))

	local dragging = false
	local function fromInput(input)
		local a = math.clamp((input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
		setValue(min + a * (max - min), true)
	end

	cardHover(card, hit, scale)
	hit.InputBegan:Connect(function(input)
		if isPress(input) then
			dragging = true
			A(knob, "Size", UDim2.fromOffset(20, 20), P.Bouncy)
			fromInput(input)
		end
	end)
	self.Window:_connect(UserInputService.InputChanged, function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
		              or input.UserInputType == Enum.UserInputType.Touch) then
			fromInput(input)
		end
	end)
	self.Window:_connect(UserInputService.InputEnded, function(input)
		if dragging and isPress(input) then
			dragging = false
			A(knob, "Size", UDim2.fromOffset(14, 14), P.Bouncy)
		end
	end)

	return {
		Frame = card,
		Get   = function()     return value end,
		Set   = function(_, v) setValue(v, true) end,
	}
end

-- ── TextInput ─────────────────────────────────────────────────────────────────
-- Set() now fires Callback with enter = true (same as pressing Enter)
function Container:AddTextInput(o)
	o = o or {}
	local card, scale = self:_card(44)
	create("TextLabel", {
		Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -200, 1, 0),
		Text = o.Text or "Input", TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	local box = create("TextBox", {
		AnchorPoint      = Vector2.new(1, 0.5),
		Position         = UDim2.new(1, -8, 0.5, 0),
		Size             = UDim2.fromOffset(170, 28),
		BackgroundColor3 = Theme.Background,
		Text             = o.Default or "",
		PlaceholderText  = o.Placeholder or "",
		PlaceholderColor3= Theme.SubText,
		TextXAlignment   = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		ClipsDescendants = true,
		Parent           = card,
	}, { corner(6), padding(10, 0, 10, 0) })
	local border   = stroke(Theme.Stroke, 1, 0)
	border.Parent  = box
	local boxScale = create("UIScale", { Parent = box })

	box.Focused:Connect(function()
		A(border,   "Color",     Theme.Accent, P.Snappy)
		A(border,   "Thickness", 2,            P.Snappy)
		A(boxScale, "Scale",     1.04,         P.Bouncy)
	end)
	box.FocusLost:Connect(function(enter)
		A(border,   "Color",     Theme.Stroke, P.Snappy)
		A(border,   "Thickness", 1,            P.Snappy)
		A(boxScale, "Scale",     1,            P.Snappy)
		if o.Callback then task.spawn(o.Callback, box.Text, enter) end
	end)
	box.MouseEnter:Connect(function() A(scale, "Scale", 1.01, P.Bouncy) end)
	box.MouseLeave:Connect(function() A(scale, "Scale", 1,    P.Snappy) end)

	return {
		Frame = card,
		Get   = function() return box.Text end,
		-- Set now fires Callback with enter = true (programmatic = confirmed)
		Set   = function(_, t)
			box.Text = t
			if o.Callback then task.spawn(o.Callback, t, true) end
		end,
	}
end

-- ── Dropdown (single-select, live-update) ────────────────────────────────────
-- New API: dd:AddOption(opt), dd:RemoveOption(opt)
-- SetOptions still works and replaces the whole list.
-- If the options table changes while the dropdown is open the list resizes live.
function Container:AddDropdown(o)
	o = o or {}
	local options  = {}
	for _, v in (o.Options or {}) do table.insert(options, v) end
	local selected = o.Default
	local HEAD, OPT = 44, 30
	local card, scale = self:_card(HEAD)
	card.ClipsDescendants = true

	create("TextLabel", {
		Position = UDim2.fromOffset(14, 0), Size = UDim2.new(0.5, -14, 0, HEAD),
		Text = o.Text or "Dropdown", TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	local valueLabel = create("TextLabel", {
		AnchorPoint    = Vector2.new(1, 0),
		Position       = UDim2.new(1, -36, 0, 0), Size = UDim2.new(0.5, -36, 0, HEAD),
		Text           = selected ~= nil and tostring(selected) or "Select…",
		TextColor3     = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate   = Enum.TextTruncate.AtEnd, Parent = card,
	})
	local chevron = create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position    = UDim2.new(1, -12, 0, 0), Size = UDim2.fromOffset(18, HEAD),
		Text = "▾", TextSize = 16, TextColor3 = Theme.SubText, Parent = card,
	})
	local list = create("ScrollingFrame", {
		Position              = UDim2.fromOffset(8, HEAD),
		Size                  = UDim2.new(1, -16, 0, 0),
		CanvasSize            = UDim2.new(),
		AutomaticCanvasSize   = Enum.AutomaticSize.Y,
		ScrollBarThickness    = 2,
		ScrollBarImageColor3  = Theme.Accent,
		Parent                = card,
	}, { create("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }) })
	local hit = create("TextButton", { Size = UDim2.new(1, 0, 0, HEAD), ZIndex = 5, Parent = card })

	local open    = false
	local buttons = {}

	local function listHeight()
		return math.min(#options * (OPT + 2), 150)
	end

	local function setOpen(v)
		open = v
		A(card,    "Size",       UDim2.new(1, 0, 0, v and (HEAD + listHeight() + 8) or HEAD), P.Snappy)
		A(chevron, "Rotation",   v and 180 or 0,                    P.Bouncy)
		A(chevron, "TextColor3", v and Theme.Accent or Theme.SubText, P.Snappy)
	end

	local function refreshHighlight()
		for _, b in buttons do
			A(b, "TextColor3", b.Name == tostring(selected) and Theme.Accent or Theme.Text, P.Snappy)
		end
	end

	local function choose(opt, fire)
		selected = opt
		valueLabel.Text = tostring(opt)
		refreshHighlight()
		if fire and o.Callback then task.spawn(o.Callback, opt) end
	end

	-- rebuild ALL option buttons from scratch
	local function rebuild()
		for _, b in buttons do b:Destroy() end
		table.clear(buttons)
		list.Size = UDim2.new(1, -16, 0, listHeight())
		for i, opt in options do
			local b = create("TextButton", {
				Name               = tostring(opt),
				Size               = UDim2.new(1, -4, 0, OPT),
				LayoutOrder        = i,
				BackgroundColor3   = Theme.SurfaceHover,
				BackgroundTransparency = 1,
				Text               = tostring(opt),
				TextColor3         = (opt == selected) and Theme.Accent or Theme.Text,
				TextXAlignment     = Enum.TextXAlignment.Left,
				Parent             = list,
			}, { corner(6), padding(10, 0, 0, 0) })
			b.MouseEnter:Connect(function()  A(b, "BackgroundTransparency", 0, P.Snappy) end)
			b.MouseLeave:Connect(function()  A(b, "BackgroundTransparency", 1, P.Snappy) end)
			b.Activated:Connect(function()
				choose(opt, true)
				setOpen(false)
			end)
			table.insert(buttons, b)
		end
	end
	rebuild()

	cardHover(card, hit, scale)
	hit.Activated:Connect(function() setOpen(not open) end)

	-- ── helpers for live mutation ────────────────────────────────────────────
	local function addOptionButton(opt, idx)
		local b = create("TextButton", {
			Name               = tostring(opt),
			Size               = UDim2.new(1, -4, 0, OPT),
			LayoutOrder        = idx,
			BackgroundColor3   = Theme.SurfaceHover,
			BackgroundTransparency = 1,
			Text               = tostring(opt),
			TextColor3         = (opt == selected) and Theme.Accent or Theme.Text,
			TextXAlignment     = Enum.TextXAlignment.Left,
			Parent             = list,
		}, { corner(6), padding(10, 0, 0, 0) })
		b.MouseEnter:Connect(function()  A(b, "BackgroundTransparency", 0, P.Snappy) end)
		b.MouseLeave:Connect(function()  A(b, "BackgroundTransparency", 1, P.Snappy) end)
		b.Activated:Connect(function()
			choose(opt, true)
			setOpen(false)
		end)
		table.insert(buttons, b)
	end

	local function updateListSize()
		list.Size = UDim2.new(1, -16, 0, listHeight())
		if open then setOpen(true) end   -- re-animate card height
	end

	return {
		Frame = card,
		Get   = function() return selected end,
		Set   = function(_, v) choose(v, true) end,

		-- Replace all options
		SetOptions = function(_, newOptions)
			options = {}
			for _, v in newOptions do table.insert(options, v) end
			rebuild()
			if open then setOpen(true) end
		end,

		-- Add a single option without closing
		AddOption = function(_, opt)
			for _, v in options do
				if v == opt then return end  -- already present
			end
			table.insert(options, opt)
			addOptionButton(opt, #options)
			updateListSize()
		end,

		-- Remove a single option; deselects if it was selected
		RemoveOption = function(_, opt)
			for i, v in options do
				if v == opt then
					table.remove(options, i)
					-- destroy matching button
					for j, b in buttons do
						if b.Name == tostring(opt) then
							b:Destroy()
							table.remove(buttons, j)
							break
						end
					end
					if selected == opt then
						selected = nil
						valueLabel.Text = "Select…"
					end
					-- re-index LayoutOrder
					for idx, b in buttons do b.LayoutOrder = idx end
					updateListSize()
					return
				end
			end
		end,
	}
end

-- ── MultiDropdown ─────────────────────────────────────────────────────────────
-- tab:AddMultiDropdown{ Text, Options, Default = {}, Max, Callback }
-- Callback receives the current selected-set as a table of values.
-- API: :Get() → table, :Set({...}) replace selection, :AddOption, :RemoveOption, :SetOptions
function Container:AddMultiDropdown(o)
	o = o or {}
	local options  = {}
	for _, v in (o.Options or {}) do table.insert(options, v) end
	local maxSel   = o.Max  -- nil = unlimited

	-- seed from Default
	local selected = {}  -- { [value] = true }
	for _, v in (o.Default or {}) do selected[v] = true end

	local HEAD, OPT = 44, 30
	local card, scale = self:_card(HEAD)
	card.ClipsDescendants = true

	create("TextLabel", {
		Position = UDim2.fromOffset(14, 0), Size = UDim2.new(0.5, -14, 0, HEAD),
		Text = o.Text or "Multi Select", TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	local valueLabel = create("TextLabel", {
		AnchorPoint  = Vector2.new(1, 0),
		Position     = UDim2.new(1, -36, 0, 0), Size = UDim2.new(0.5, -36, 0, HEAD),
		Text         = "None", TextColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd, Parent = card,
	})
	local chevron = create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position    = UDim2.new(1, -12, 0, 0), Size = UDim2.fromOffset(18, HEAD),
		Text = "▾", TextSize = 16, TextColor3 = Theme.SubText, Parent = card,
	})
	local list = create("ScrollingFrame", {
		Position             = UDim2.fromOffset(8, HEAD),
		Size                 = UDim2.new(1, -16, 0, 0),
		CanvasSize           = UDim2.new(),
		AutomaticCanvasSize  = Enum.AutomaticSize.Y,
		ScrollBarThickness   = 2,
		ScrollBarImageColor3 = Theme.Accent,
		Parent               = card,
	}, { create("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }) })
	local hit = create("TextButton", { Size = UDim2.new(1, 0, 0, HEAD), ZIndex = 5, Parent = card })

	local open    = false
	local buttons = {}

	local function summaryText()
		local parts = {}
		for _, v in options do
			if selected[v] then table.insert(parts, tostring(v)) end
		end
		return #parts == 0 and "None" or table.concat(parts, ", ")
	end

	local function fireCallback()
		if o.Callback then
			local t = {}
			for _, v in options do if selected[v] then table.insert(t, v) end end
			task.spawn(o.Callback, t)
		end
	end

	local function updateLabel()
		valueLabel.Text = summaryText()
	end

	local function listHeight()
		return math.min(#options * (OPT + 2), 150)
	end

	local function setOpen(v)
		open = v
		A(card,    "Size",       UDim2.new(1, 0, 0, v and (HEAD + listHeight() + 8) or HEAD), P.Snappy)
		A(chevron, "Rotation",   v and 180 or 0,                     P.Bouncy)
		A(chevron, "TextColor3", v and Theme.Accent or Theme.SubText,  P.Snappy)
	end

	local function refreshChecks()
		for _, b in buttons do
			local chk = b:FindFirstChild("_check")
			if chk then
				local on = selected[b:FindFirstChild("_value") and b._value or nil]
				-- we store value in an attribute instead
				local bval = b:GetAttribute("_val")
				local isOn = selected[bval] == true
				A(chk,  "BackgroundColor3", isOn and Theme.Accent or Theme.Stroke, P.Snappy)
				A(b,    "TextColor3",       isOn and Theme.Accent or Theme.Text,   P.Snappy)
			end
		end
	end

	local function rebuild()
		for _, b in buttons do b:Destroy() end
		table.clear(buttons)
		list.Size = UDim2.new(1, -16, 0, listHeight())

		for i, opt in options do
			local isOn = selected[opt] == true
			local b = create("TextButton", {
				Name               = tostring(opt),
				Size               = UDim2.new(1, -4, 0, OPT),
				LayoutOrder        = i,
				BackgroundColor3   = Theme.SurfaceHover,
				BackgroundTransparency = 1,
				Text               = tostring(opt),
				TextColor3         = isOn and Theme.Accent or Theme.Text,
				TextXAlignment     = Enum.TextXAlignment.Left,
				Parent             = list,
			}, { corner(6), padding(34, 0, 0, 0) })
			b:SetAttribute("_val", tostring(opt))  -- store as string key
			-- checkmark box
			local chk = create("Frame", {
				Name             = "_check",
				AnchorPoint      = Vector2.new(0, 0.5),
				Position         = UDim2.new(0, -24, 0.5, 0),
				Size             = UDim2.fromOffset(16, 16),
				BackgroundColor3 = isOn and Theme.Accent or Theme.Stroke,
				Parent           = b,
			}, { corner(4) })
			-- tick mark
			local tick = create("TextLabel", {
				Size       = UDim2.fromScale(1, 1),
				Text       = "✓",
				TextSize   = 11,
				Font       = Theme.FontBold,
				TextColor3 = Color3.new(1, 1, 1),
				BackgroundTransparency = 1,
				Parent     = chk,
			})
			tick.Visible = isOn

			b.MouseEnter:Connect(function()  A(b, "BackgroundTransparency", 0, P.Snappy) end)
			b.MouseLeave:Connect(function()  A(b, "BackgroundTransparency", 1, P.Snappy) end)
			b.Activated:Connect(function()
				local key = tostring(opt)
				if selected[opt] then
					selected[opt] = nil
					A(chk,  "BackgroundColor3", Theme.Stroke, P.Snappy)
					A(b,    "TextColor3",       Theme.Text,   P.Snappy)
					tick.Visible = false
				else
					-- check max
					if maxSel then
						local count = 0
						for _ in selected do count += 1 end
						if count >= maxSel then return end
					end
					selected[opt] = true
					A(chk,  "BackgroundColor3", Theme.Accent, P.Snappy)
					A(b,    "TextColor3",       Theme.Accent, P.Snappy)
					tick.Visible = true
				end
				updateLabel()
				fireCallback()
			end)
			table.insert(buttons, b)
		end
	end
	rebuild()
	updateLabel()

	cardHover(card, hit, scale)
	hit.Activated:Connect(function() setOpen(not open) end)

	local function updateListSize()
		list.Size = UDim2.new(1, -16, 0, listHeight())
		if open then setOpen(true) end
	end

	return {
		Frame = card,
		Get   = function()
			local t = {}
			for _, v in options do if selected[v] then table.insert(t, v) end end
			return t
		end,
		Set   = function(_, newSel)
			selected = {}
			for _, v in newSel do selected[v] = true end
			rebuild()
			updateLabel()
			fireCallback()
		end,
		SetOptions = function(_, newOptions)
			options = {}
			for _, v in newOptions do table.insert(options, v) end
			-- prune selection to only valid options
			local validSet = {}
			for _, v in options do validSet[v] = true end
			for k in selected do if not validSet[k] then selected[k] = nil end end
			rebuild(); updateLabel()
			if open then setOpen(true) end
		end,
		AddOption = function(_, opt)
			for _, v in options do if v == opt then return end end
			table.insert(options, opt)
			rebuild()
			updateListSize()
		end,
		RemoveOption = function(_, opt)
			for i, v in options do
				if v == opt then
					table.remove(options, i)
					selected[opt] = nil
					rebuild(); updateLabel()
					updateListSize()
					return
				end
			end
		end,
	}
end

-- ── ColorPicker ───────────────────────────────────────────────────────────────
-- tab:AddColorPicker{ Text, Default = Color3, Callback }
-- Collapsed: shows a color swatch. Expanded: SV square + H strip + hex input.
function Container:AddColorPicker(o)
	o = o or {}
	local HEAD      = 44
	local EXPANDED  = 44 + 160 + 8  -- header + picker body + padding
	local card, scale = self:_card(HEAD)
	card.ClipsDescendants = true

	local color   = o.Default or Color3.fromRGB(124, 92, 255)
	local h, s, v = rgbToHsv(color)

	-- ── header ──────────────────────────────────────────────────────────────
	create("TextLabel", {
		Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -80, 0, HEAD),
		Text = o.Text or "Color", TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	local swatch = create("Frame", {
		AnchorPoint      = Vector2.new(1, 0.5),
		Position         = UDim2.new(1, -36, 0.5, 0),
		Size             = UDim2.fromOffset(44, 24),
		BackgroundColor3 = color,
		Parent           = card,
	}, { corner(6), stroke(Theme.Stroke, 1, 0.3) })
	local chevron = create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position    = UDim2.new(1, -12, 0, 0), Size = UDim2.fromOffset(18, HEAD),
		Text = "▾", TextSize = 16, TextColor3 = Theme.SubText, Parent = card,
	})
	local hit = create("TextButton", { Size = UDim2.new(1, 0, 0, HEAD), ZIndex = 5, Parent = card })

	-- ── picker body ──────────────────────────────────────────────────────────
	local body = create("Frame", {
		Position = UDim2.new(0, 8, 0, HEAD + 4),
		Size     = UDim2.new(1, -16, 0, 152),
		BackgroundTransparency = 1,
		Parent   = card,
	})

	-- SV square (128×128)
	local sqSize = 128
	local sq = create("Frame", {
		Size             = UDim2.fromOffset(sqSize, sqSize),
		BackgroundColor3 = Color3.new(1, 0, 0),  -- tinted by h
		Parent           = body,
	}, { corner(6) })
	-- white-to-transparent gradient (left→right = sat 0→1, actually we overlay two gradients)
	local sqWhite = create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = sq,
	}, { corner(6), create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(1,1,1)),
			ColorSequenceKeypoint.new(1, Color3.new(1,1,1,0)),  -- transparent white
		}),
	}) })
	-- black gradient top→bottom
	local sqBlack = create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		Parent = sq,
	}, { corner(6), create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(0,0,0,0)),
			ColorSequenceKeypoint.new(1, Color3.new(0,0,0)),
		}),
	}) })
	-- SV cursor
	local svCursor = create("Frame", {
		AnchorPoint      = Vector2.new(0.5, 0.5),
		Size             = UDim2.fromOffset(12, 12),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex           = 5,
		Parent           = sq,
	}, { pill(), stroke(Color3.new(0,0,0), 1, 0) })

	-- Hue strip (right of square, 12px wide)
	local hStrip = create("Frame", {
		Position = UDim2.fromOffset(sqSize + 8, 0),
		Size     = UDim2.fromOffset(12, sqSize),
		Parent   = body,
	}, { corner(6) })
	-- rainbow gradient
	local hGrad = create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0,    Color3.fromHSV(0,   1, 1)),
			ColorSequenceKeypoint.new(1/6,  Color3.fromHSV(1/6, 1, 1)),
			ColorSequenceKeypoint.new(2/6,  Color3.fromHSV(2/6, 1, 1)),
			ColorSequenceKeypoint.new(3/6,  Color3.fromHSV(3/6, 1, 1)),
			ColorSequenceKeypoint.new(4/6,  Color3.fromHSV(4/6, 1, 1)),
			ColorSequenceKeypoint.new(5/6,  Color3.fromHSV(5/6, 1, 1)),
			ColorSequenceKeypoint.new(1,    Color3.fromHSV(1,   1, 1)),
		}),
		Parent = hStrip,
	})
	hStrip.BackgroundColor3 = Color3.new(1,1,1)  -- gets coloured by gradient
	-- hue cursor bar
	local hCursor = create("Frame", {
		AnchorPoint      = Vector2.new(0.5, 0.5),
		Size             = UDim2.new(1, 4, 0, 4),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex           = 5,
		Parent           = hStrip,
	}, { pill(), stroke(Color3.new(0,0,0), 1, 0) })

	-- Hex input
	local hexBox = create("TextBox", {
		Position         = UDim2.new(0, 0, 0, sqSize + 8),
		Size             = UDim2.new(1, 0, 0, 26),
		BackgroundColor3 = Theme.Background,
		Text             = colorToHex(color),
		PlaceholderText  = "RRGGBB",
		PlaceholderColor3= Theme.SubText,
		TextXAlignment   = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		Parent           = body,
	}, { corner(6), padding(8, 0, 8, 0), stroke(Theme.Stroke, 1, 0) })

	-- ── update functions ─────────────────────────────────────────────────────
	local function applyColor(fireCallback)
		color = hsvToRgb(h, s, v)
		swatch.BackgroundColor3 = color
		sq.BackgroundColor3     = Color3.fromHSV(h, 1, 1)
		-- cursor positions
		svCursor.Position = UDim2.fromScale(s, 1 - v)
		hCursor.Position  = UDim2.new(0.5, 0, h, 0)
		hexBox.Text       = colorToHex(color)
		if fireCallback and o.Callback then task.spawn(o.Callback, color) end
	end
	applyColor(false)

	-- SV drag
	local sqDragging = false
	local sqHit = create("TextButton", { Size = UDim2.fromScale(1, 1), ZIndex = 10, Parent = sq })
	sqHit.InputBegan:Connect(function(input)
		if isPress(input) then sqDragging = true end
	end)
	self.Window:_connect(UserInputService.InputChanged, function(input)
		if sqDragging and (input.UserInputType == Enum.UserInputType.MouseMovement
		               or  input.UserInputType == Enum.UserInputType.Touch) then
			local rel = (Vector2.new(input.Position.X, input.Position.Y) - sq.AbsolutePosition) / sq.AbsoluteSize
			s = math.clamp(rel.X, 0, 1)
			v = 1 - math.clamp(rel.Y, 0, 1)
			applyColor(true)
		end
	end)
	self.Window:_connect(UserInputService.InputEnded, function(input)
		if isPress(input) then sqDragging = false end
	end)

	-- Hue drag
	local hDragging = false
	local hHit = create("TextButton", { Size = UDim2.fromScale(1, 1), ZIndex = 10, Parent = hStrip })
	hHit.InputBegan:Connect(function(input)
		if isPress(input) then hDragging = true end
	end)
	self.Window:_connect(UserInputService.InputChanged, function(input)
		if hDragging and (input.UserInputType == Enum.UserInputType.MouseMovement
		               or  input.UserInputType == Enum.UserInputType.Touch) then
			local rel = (input.Position.Y - hStrip.AbsolutePosition.Y) / hStrip.AbsoluteSize.Y
			h = math.clamp(rel, 0, 1)
			applyColor(true)
		end
	end)
	self.Window:_connect(UserInputService.InputEnded, function(input)
		if isPress(input) then hDragging = false end
	end)

	-- Hex input
	hexBox.FocusLost:Connect(function()
		local c = hexToColor(hexBox.Text)
		if c then
			h, s, v = rgbToHsv(c)
			applyColor(true)
		else
			hexBox.Text = colorToHex(color)  -- revert bad input
		end
	end)

	-- ── open/close ───────────────────────────────────────────────────────────
	local open = false
	local function setOpen(val)
		open = val
		A(card,    "Size",       UDim2.new(1, 0, 0, val and EXPANDED or HEAD), P.Snappy)
		A(chevron, "Rotation",   val and 180 or 0,                              P.Bouncy)
		A(chevron, "TextColor3", val and Theme.Accent or Theme.SubText,         P.Snappy)
		body.Visible = val
	end
	body.Visible = false

	cardHover(card, hit, scale)
	hit.Activated:Connect(function() setOpen(not open) end)

	return {
		Frame = card,
		Get   = function() return color end,
		Set   = function(_, c)
			h, s, v = rgbToHsv(c)
			applyColor(true)
		end,
	}
end

-- ── Keybind picker ────────────────────────────────────────────────────────────
-- tab:AddKeybind{ Text, Default = Enum.KeyCode.X, Callback }
-- Click the button to start listening; press any key to bind it.
-- Press Escape to cancel. Right-click the button to clear (sets Unknown).
function Container:AddKeybind(o)
	o = o or {}
	local bound    = o.Default or Enum.KeyCode.Unknown
	local card, scale = self:_card(44)
	local listening = false

	create("TextLabel", {
		Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -150, 1, 0),
		Text = o.Text or "Keybind", TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})

	local btn = create("TextButton", {
		AnchorPoint      = Vector2.new(1, 0.5),
		Position         = UDim2.new(1, -10, 0.5, 0),
		Size             = UDim2.fromOffset(130, 28),
		BackgroundColor3 = Theme.Background,
		Text             = keyName(bound),
		Font             = Theme.FontBold,
		TextSize         = 13,
		Parent           = card,
	}, { corner(6), stroke(Theme.Stroke, 1, 0) })
	local btnScale = create("UIScale", { Parent = btn })
	local bdrStroke = btn:FindFirstChildWhichIsA("UIStroke")  -- the stroke we just made

	local hitCard = create("TextButton", { Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = card })

	local function stopListen()
		listening = false
		btn.Text = keyName(bound)
		A(bdrStroke, "Color", Theme.Stroke, P.Snappy)
		A(btn, "BackgroundColor3", Theme.Background, P.Snappy)
	end

	local function startListen()
		listening = true
		btn.Text = "…"
		A(bdrStroke, "Color",     Theme.Accent, P.Snappy)
		A(btn, "BackgroundColor3", Theme.SurfaceHover, P.Snappy)
	end

	btn.Activated:Connect(function()
		if listening then stopListen() else startListen() end
	end)
	btn.MouseButton2Click:Connect(function()
		-- right-click to clear
		bound = Enum.KeyCode.Unknown
		stopListen()
		if o.Callback then task.spawn(o.Callback, bound) end
	end)

	btn.MouseEnter:Connect(function() A(btnScale, "Scale", 1.04, P.Bouncy) end)
	btn.MouseLeave:Connect(function() A(btnScale, "Scale", 1,    P.Snappy) end)

	-- card hover
	hitCard.MouseEnter:Connect(function()
		A(card,  "BackgroundColor3", Theme.SurfaceHover, P.Snappy)
		A(scale, "Scale",            1.01,               P.Bouncy)
	end)
	hitCard.MouseLeave:Connect(function()
		A(card,  "BackgroundColor3", Theme.Surface, P.Snappy)
		A(scale, "Scale",            1,             P.Snappy)
	end)
	-- clicking the card (not the btn) while not listening has no effect
	hitCard.Activated:Connect(function() end)

	self.Window:_connect(UserInputService.InputBegan, function(input, processed)
		if not listening then return end
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		if input.KeyCode == Enum.KeyCode.Escape then
			stopListen()
			return
		end
		-- ignore modifier-only presses
		local mods = {
			Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift,
			Enum.KeyCode.LeftControl, Enum.KeyCode.RightControl,
			Enum.KeyCode.LeftAlt, Enum.KeyCode.RightAlt,
			Enum.KeyCode.LeftSuper, Enum.KeyCode.RightSuper,
		}
		for _, m in mods do
			if input.KeyCode == m then return end
		end
		bound = input.KeyCode
		stopListen()
		if o.Callback then task.spawn(o.Callback, bound) end
	end)

	return {
		Frame  = card,
		Get    = function() return bound end,
		Set    = function(_, key)
			bound = key
			btn.Text = keyName(key)
			if o.Callback then task.spawn(o.Callback, key) end
		end,
	}
end

-- ── Progress ──────────────────────────────────────────────────────────────────
function Container:AddProgress(o)
	o = o or {}
	local card = self:_card(50)
	create("TextLabel", {
		Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -100, 0, 18),
		Text = o.Text or "Progress", TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	local pct = create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 8),
		Size = UDim2.fromOffset(80, 18), Font = Theme.FontBold,
		TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Right,
		Parent = card,
	})
	local track = create("Frame", {
		Position = UDim2.new(0, 14, 0, 32), Size = UDim2.new(1, -28, 0, 8),
		BackgroundColor3 = Theme.Stroke, Parent = card,
	}, { pill() })
	local fill = create("Frame", {
		Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = track,
	}, { pill(), create("UIGradient", { Color = ColorSequence.new(Theme.Accent, Theme.AccentAlt) }) })

	local function set(a, instant)
		a = math.clamp(a, 0, 1)
		put(fill, "Size", UDim2.new(a, 0, 1, 0), { 12, 1 }, instant)
		pct.Text = math.floor(a * 100 + 0.5) .. "%"
	end
	set(o.Value or 0, true)

	return {
		Frame = card,
		Set   = function(_, a) set(a, false) end,
	}
end

--------------------------------------------------------------------------------
-- Storage layer (writefile / ReplicatedStorage fallback)
--------------------------------------------------------------------------------
-- All persistence goes through these two functions. On executors that expose
-- writefile/readfile/isfile they use the filesystem; everywhere else they
-- store data as StringValues inside a folder tree in ReplicatedStorage so
-- the values survive as long as the game session does (not across sessions,
-- but they're always readable by other LocalScripts on the same client).
--
--   Nova.Storage.Save(namespace, key, json_string)
--   Nova.Storage.Load(namespace, key)  → string | nil
--   Nova.Storage.Folder  -- e.g.  "NovaUI/"  (filesystem prefix)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HAS_FS = type(writefile) == "function"
             and type(readfile) == "function"
             and type(isfile)   == "function"

local Storage = {}
Nova.Storage  = Storage

Storage.Folder = "NovaUI/"  -- filesystem folder prefix (no trailing slash needed separately)

-- Ensure the filesystem folder exists (some executors need makefolder)
if HAS_FS then
	pcall(function()
		if type(makefolder) == "function" and not isfolder(Storage.Folder) then
			makefolder(Storage.Folder)
		end
	end)
end

-- Returns or creates the RS folder tree: ReplicatedStorage/NovaUI/<namespace>/
local function getRSFolder(namespace)
	local root = ReplicatedStorage:FindFirstChild("NovaUI")
	if not root then
		root = Instance.new("Folder")
		root.Name = "NovaUI"
		root.Parent = ReplicatedStorage
	end
	local ns = root:FindFirstChild(namespace)
	if not ns then
		ns = Instance.new("Folder")
		ns.Name = namespace
		ns.Parent = root
	end
	return ns
end

function Storage.Save(namespace, key, data)
	-- data should be a JSON string
	if HAS_FS then
		local path = Storage.Folder .. namespace .. "_" .. key .. ".json"
		pcall(writefile, path, data)
	else
		local folder = getRSFolder(namespace)
		local sv = folder:FindFirstChild(key)
		if not sv then
			sv = Instance.new("StringValue")
			sv.Name   = key
			sv.Parent = folder
		end
		sv.Value = data
	end
end

function Storage.Load(namespace, key)
	if HAS_FS then
		local path = Storage.Folder .. namespace .. "_" .. key .. ".json"
		local ok, data = pcall(function()
			if isfile(path) then return readfile(path) end
			return nil
		end)
		return ok and data or nil
	else
		local folder = getRSFolder(namespace)
		local sv = folder:FindFirstChild(key)
		return sv and sv.Value ~= "" and sv.Value or nil
	end
end

-- Tiny JSON encoder/decoder for the simple types NovaUI needs
-- (numbers, booleans, strings, Color3 as hex, KeyCode as name, arrays, dicts)
local JSON = {}

local function jsonEncode(val)
	local t = type(val)
	if t == "nil"     then return "null"
	elseif t == "boolean" then return val and "true" or "false"
	elseif t == "number"  then return tostring(val)
	elseif t == "string"  then
		-- escape backslash, quote, newline
		val = val:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n')
		return '"' .. val .. '"'
	elseif t == "table" then
		-- check if array
		local isArr = (#val > 0)
		if isArr then
			local parts = {}
			for _, v in val do table.insert(parts, jsonEncode(v)) end
			return "[" .. table.concat(parts, ",") .. "]"
		else
			local parts = {}
			for k, v in val do
				table.insert(parts, '"' .. tostring(k) .. '":' .. jsonEncode(v))
			end
			return "{" .. table.concat(parts, ",") .. "}"
		end
	end
	return "null"
end

-- Very small recursive descent parser – only handles what we write
local function jsonDecode(s)
	local pos = 1

	local function skip()
		while pos <= #s and s:sub(pos,pos):match("%s") do pos += 1 end
	end

	local parseVal  -- forward decl
	local function parseStr()
		pos += 1  -- skip opening "
		local buf = {}
		while pos <= #s do
			local c = s:sub(pos, pos)
			if c == '"' then pos += 1; break end
			if c == '\\' then
				pos += 1
				local e = s:sub(pos, pos)
				if     e == '"'  then buf[#buf+1] = '"'
				elseif e == '\\' then buf[#buf+1] = '\\'
				elseif e == 'n'  then buf[#buf+1] = '\n'
				else buf[#buf+1] = e end
			else
				buf[#buf+1] = c
			end
			pos += 1
		end
		return table.concat(buf)
	end

	local function parseArr()
		pos += 1; skip()
		local arr = {}
		if s:sub(pos,pos) == ']' then pos += 1; return arr end
		repeat
			skip(); arr[#arr+1] = parseVal(); skip()
			local c = s:sub(pos,pos); pos += 1
		until c == ']' or pos > #s
		return arr
	end

	local function parseObj()
		pos += 1; skip()
		local obj = {}
		if s:sub(pos,pos) == '}' then pos += 1; return obj end
		repeat
			skip()
			local k = parseStr(); skip()
			pos += 1  -- ':'
			skip()
			obj[k] = parseVal(); skip()
			local c = s:sub(pos,pos); pos += 1
		until c == '}' or pos > #s
		return obj
	end

	parseVal = function()
		skip()
		local c = s:sub(pos, pos)
		if c == '"' then return parseStr()
		elseif c == '[' then return parseArr()
		elseif c == '{' then return parseObj()
		elseif s:sub(pos, pos+3) == "true"  then pos += 4; return true
		elseif s:sub(pos, pos+4) == "false" then pos += 5; return false
		elseif s:sub(pos, pos+3) == "null"  then pos += 4; return nil
		else
			-- number
			local num = s:match("^-?%d+%.?%d*", pos)
			if num then pos += #num; return tonumber(num) end
		end
		return nil
	end

	return parseVal()
end

JSON.encode = jsonEncode
JSON.decode = jsonDecode
Nova.JSON   = JSON  -- expose in case users want it

-- Value serialisers / deserialisers for component types
local function serializeValue(val)
	local t = typeof(val)
	if t == "boolean" or t == "number" or t == "string" then
		return val
	elseif t == "Color3" then
		return { __type = "Color3", hex = colorToHex(val) }
	elseif t == "EnumItem" then
		return { __type = "KeyCode", name = val.Name }
	elseif t == "table" then  -- multi-dropdown array
		return val
	end
	return nil
end

local function deserializeValue(raw)
	if type(raw) == "table" then
		if raw.__type == "Color3" then
			return hexToColor(raw.hex) or Color3.new(1,1,1)
		elseif raw.__type == "KeyCode" then
			return Enum.KeyCode[raw.name] or Enum.KeyCode.Unknown
		else
			return raw  -- plain array (multi-dropdown)
		end
	end
	return raw
end

--------------------------------------------------------------------------------
-- Shared UI helper: mini action button row (reused by Config + Theme tabs)
--------------------------------------------------------------------------------
-- Returns nothing; populates `parent` frame with N equal-width gradient buttons.
-- btns = { { text, accentColor, callback }, ... }
local function actionRow(parent, btns)
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding       = UDim.new(0, 6),
		SortOrder     = Enum.SortOrder.LayoutOrder,
		Parent        = parent,
	})
	padding(0, 4, 0, 4).Parent = parent
	local n = #btns
	for i, b in btns do
		local grad = create("UIGradient", {
			Color    = ColorSequence.new(b[2], Theme.AccentAlt),
			Rotation = 20,
		})
		local face = create("Frame", {
    		Size             = UDim2.new(1/n, if n > 1 then -math.ceil(6*(n-1)/n) else 0, 1, 0),
    		BackgroundColor3 = Color3.new(1,1,1),
    		LayoutOrder      = i,
    		Parent           = parent,
		}, { corner(7), grad })
		create("TextLabel", {
			Size       = UDim2.fromScale(1,1),
			Text       = b[1],
			Font       = Theme.FontBold,
			TextColor3 = Color3.new(1,1,1),
			TextSize   = 12,
			ZIndex     = 3,
			Parent     = face,
		})
		local sc  = create("UIScale", { Parent = face })
		local hit = create("TextButton", { Size = UDim2.fromScale(1,1), ZIndex = 5, Parent = face })
		hit.MouseEnter:Connect(function()       A(sc, "Scale", 1.04, P.Bouncy) end)
		hit.MouseLeave:Connect(function()       A(sc, "Scale", 1,    P.Snappy) end)
		hit.MouseButton1Down:Connect(function() A(sc, "Scale", 0.94, P.Snappy) end)
		hit.MouseButton1Up:Connect(function()   A(sc, "Scale", 1.04, P.Bouncy) end)
		hit.InputBegan:Connect(function(inp) if isPress(inp) then ripple(face, inp) end end)
		hit.Activated:Connect(function() task.spawn(b[3]) end)
	end
end

--------------------------------------------------------------------------------
-- Config system  (multi-profile, game/global scope, selector, auto-load)
--------------------------------------------------------------------------------
--[[
  Mount with:   cfgTab:MountConfig()

  Tag any component on any tab with Key = "..." to have it automatically
  saved/loaded by the active config profile:
    tab:AddToggle{ Text = "God Mode", Key = "godMode", Default = false, Callback = fn }

  The GUI tab provides:
    • Game / Global scope toggle (Game = per-PlaceId, Global = shared across games)
    • Profile dropdown selector
    • Profile name text input
    • Save New, Overwrite, Load, Delete, Reset Defaults action buttons
    • Auto-loads the last used profile on startup for each scope

  To register a component manually (e.g. created outside a tab):
    Nova._cfg:Register("myKey", component)
  Nova._cfg always points to the currently active scope's Config instance.
]]

-- Which Add* methods auto-register when Key is present
local AUTO_REGISTER_METHODS = {
	"AddToggle","AddSlider","AddTextInput","AddDropdown",
	"AddMultiDropdown","AddColorPicker","AddKeybind",
}

-- Auto-derived namespaces
local NS_GAME   = "NovaConfig_" .. tostring(game.PlaceId)
local NS_GLOBAL = "NovaConfig_Global"

local Config = {}
Config.__index = Config
-- Config is internal; use tab:MountConfig() for the GUI-driven workflow.

local function _newConfig(namespace)
	return setmetatable({
		_namespace     = namespace,
		_entries       = {},
		_activeProfile = nil,
	}, Config)
end
-- Expose read-only access to the active config instance for manual Register calls.
-- Nova._cfg is set to the active scope's instance by MountConfig's scope toggle.

-- Two built-in instances (game-scoped and global)
local _cfgGame   = _newConfig(NS_GAME)
local _cfgGlobal = _newConfig(NS_GLOBAL)
Nova._cfgGame   = _cfgGame
Nova._cfgGlobal = _cfgGlobal
-- Nova._cfg points to whichever is currently active (starts as game)
Nova._cfg = _cfgGame

-- ── internal helpers ──────────────────────────────────────────────────────────

function Config:_getIndex()
	local raw = Storage.Load(self._namespace, "_index")
	if not raw then return {} end
	local ok, t = pcall(JSON.decode, raw)
	return (ok and type(t) == "table") and t or {}
end

function Config:_setIndex(list)
	Storage.Save(self._namespace, "_index", JSON.encode(list))
end

function Config:_profileExists(name)
	for _, n in self:_getIndex() do if n == name then return true end end
	return false
end

function Config:_addToIndex(name)
	local idx = self:_getIndex()
	for _, n in idx do if n == name then return end end
	table.insert(idx, name); self:_setIndex(idx)
end

function Config:_removeFromIndex(name)
	local idx = self:_getIndex()
	for i, n in idx do if n == name then table.remove(idx, i); break end end
	self:_setIndex(idx)
end

function Config:_snapshot()
	local d = {}
	for k, e in self._entries do d[k] = serializeValue(e.component:Get()) end
	return d
end

function Config:_applyData(data)
	for k, e in self._entries do
		if data[k] ~= nil then
			local val = deserializeValue(data[k])
			if val ~= nil then pcall(function() e.component:Set(val) end) end
		end
	end
end

-- ── public API ────────────────────────────────────────────────────────────────

function Config:SaveProfile(name)
	name = (name ~= nil and tostring(name):match("^%s*(.-)%s*$")) or ""
	if name == "" then
		Nova.Notify{ Title="Config", Text="Profile name cannot be empty.", Type="warning", Duration=3 }
		return false
	end
	Storage.Save(self._namespace, name, JSON.encode(self:_snapshot()))
	self:_addToIndex(name)
	self._activeProfile = name
	Storage.Save(self._namespace, "_active", JSON.encode(name))
	return true
end

function Config:LoadProfile(name)
	local raw = Storage.Load(self._namespace, name)
	if not raw then
		Nova.Notify{ Title="Config", Text='Profile "'..tostring(name)..'" not found.', Type="error", Duration=3 }
		return false
	end
	local ok, data = pcall(JSON.decode, raw)
	if not ok or type(data) ~= "table" then
		Nova.Notify{ Title="Config", Text="Profile data corrupted.", Type="error", Duration=3 }
		return false
	end
	self:_applyData(data)
	self._activeProfile = name
	Storage.Save(self._namespace, "_active", JSON.encode(name))
	return true
end

function Config:DeleteProfile(name)
	Storage.Save(self._namespace, name, "")
	self:_removeFromIndex(name)
	if self._activeProfile == name then
		self._activeProfile = nil
		Storage.Save(self._namespace, "_active", JSON.encode(nil))
	end
end

function Config:ResetDefaults()
	for _, e in self._entries do
		if e.default ~= nil then pcall(function() e.component:Set(e.default) end) end
	end
end

function Config:Register(key, component, default)
	if default == nil then pcall(function() default = component:Get() end) end
	self._entries[key] = { component = component, default = default }
end

function Config:AutoLoad()
	local raw = Storage.Load(self._namespace, "_active")
	if not raw then return nil end
	local ok, name = pcall(JSON.decode, raw)
	if not ok or type(name) ~= "string" or name == "" then return nil end
	if self:LoadProfile(name) then return name end
	return nil
end

-- ── tab UI ────────────────────────────────────────────────────────────────────

-- Builds the profile-management UI section for whichever cfg is active.
-- Returns a refresh function so the Game/Global toggle can rebuild the list.
local function buildConfigUI(tab, cfg, selectorComp, nameInput)
	-- refresh the dropdown to this cfg's profile list
	local idx = cfg:_getIndex()
	selectorComp:SetOptions(idx)
	selectorComp:Set(idx[1])

	-- wire action rows to the new cfg
	-- (row buttons close over `cfg` via the refresh, so we rebuild them)
	local function overwrite()
		local sel = selectorComp:Get()
		if not sel then
			Nova.Notify{ Title="Config", Text="Select a profile first.", Type="warning", Duration=3 }
			return
		end
		Nova.Dialog{
			Title   = 'Overwrite "'..tostring(sel)..'"?',
			Text    = "This will replace its saved values.",
			Buttons = {
				{ Text = "Overwrite", Primary = true, Callback = function()
					if cfg:SaveProfile(sel) then
						Nova.Notify{ Title="Config", Text='Saved "'..sel..'"', Type="success", Duration=2 }
					end
				end },
				{ Text = "Cancel" },
			},
		}
	end

	local function saveNew()
		local name = nameInput:Get():match("^%s*(.-)%s*$")
		if name == "" then
			Nova.Notify{ Title="Config", Text="Type a name first.", Type="warning", Duration=3 }
			return
		end
		if cfg:_profileExists(name) then
			Nova.Dialog{
				Title   = 'Profile "'..name..'" exists',
				Text    = "Overwrite it?",
				Buttons = {
					{ Text = "Overwrite", Primary = true, Callback = function()
						if cfg:SaveProfile(name) then
							selectorComp:AddOption(name)
							selectorComp:Set(name)
							nameInput:Set("")
							Nova.Notify{ Title="Config", Text='Saved "'..name..'"', Type="success", Duration=2 }
						end
					end },
					{ Text = "Cancel" },
				},
			}
		else
			if cfg:SaveProfile(name) then
				selectorComp:AddOption(name)
				selectorComp:Set(name)
				nameInput:Set("")
				Nova.Notify{ Title="Config", Text='Created "'..name..'"', Type="success", Duration=2 }
			end
		end
	end

	local function load()
		local sel = selectorComp:Get()
		if not sel then
			Nova.Notify{ Title="Config", Text="No profile selected.", Type="warning", Duration=3 }
			return
		end
		if cfg:LoadProfile(sel) then
			Nova.Notify{ Title="Config", Text='Loaded "'..sel..'"', Type="info", Duration=2 }
		end
	end

	local function delete()
		local sel = selectorComp:Get()
		if not sel then
			Nova.Notify{ Title="Config", Text="No profile selected.", Type="warning", Duration=3 }
			return
		end
		Nova.Dialog{
			Title   = 'Delete "'..tostring(sel)..'"?',
			Text    = "This cannot be undone.",
			Buttons = {
				{ Text = "Delete", Primary = true, Callback = function()
					cfg:DeleteProfile(sel)
					selectorComp:RemoveOption(sel)
					Nova.Notify{ Title="Config", Text='Deleted "'..sel..'"', Type="info", Duration=2 }
				end },
				{ Text = "Cancel" },
			},
		}
	end

	local function resetDefaults()
		Nova.Dialog{
			Title   = "Reset to Defaults",
			Text    = "Restore all settings to their default values?",
			Buttons = {
				{ Text = "Reset", Primary = true, Callback = function()
					cfg:ResetDefaults()
					Nova.Notify{ Title="Config", Text="Defaults restored.", Type="info", Duration=2 }
				end },
				{ Text = "Cancel" },
			},
		}
	end

	return overwrite, saveNew, load, delete, resetDefaults
end

function Container:MountConfig()
	local tab = self

	-- Patch Add* to auto-register Key'd components into whichever cfg is active
	for _, method in AUTO_REGISTER_METHODS do
		local original = Container[method]
		if original then
			tab[method] = function(self2, o2, ...)
				local comp = original(self2, o2, ...)
				if o2 and o2.Key and comp then
					Nova._cfg:Register(o2.Key, comp, o2.Default)
				end
				return comp
			end
		end
	end

	-- ── Game / Global toggle ─────────────────────────────────────────────────
	tab:AddSection("Config Scope")

	local scopeRow = tab:_card(40, true)
	local isGame   = true   -- current scope

	-- These are filled after the profile UI is built below
	local selectorComp, nameInput
	local overwrite, saveNew, load, delete, resetDefaults

	local function switchScope(toGame)
		isGame  = toGame
		Nova._cfg = toGame and _cfgGame or _cfgGlobal
		overwrite, saveNew, load, delete, resetDefaults =
			buildConfigUI(tab, Nova._cfg, selectorComp, nameInput)
		task.defer(function()
			local loaded = Nova._cfg:AutoLoad()
			if loaded then
				selectorComp:Set(loaded)
				Nova.Notify{
					Title = "Config",
					Text  = 'Auto-loaded "'..loaded..'" ('..(toGame and "Game" or "Global")..')',
					Type  = "info", Duration = 2,
				}
			end
		end)
	end

	actionRow(scopeRow, {
		{ "🎮 Game",   Theme.Accent,    function() switchScope(true)  end },
		{ "🌐 Global", Theme.AccentAlt, function() switchScope(false) end },
	})

	-- ── Profile selector + name input ────────────────────────────────────────
	tab:AddSection("Profile")

	local initProfiles = _cfgGame:_getIndex()
	selectorComp = tab:AddDropdown{
		Text    = "Active Profile",
		Options = initProfiles,
		Default = initProfiles[1],
	}

	nameInput = tab:AddTextInput{
		Text        = "Profile Name",
		Placeholder = "Enter name…",
	}

	-- ── Action rows ──────────────────────────────────────────────────────────
	tab:AddSection("Actions")

	local row1 = tab:_card(40, true)
	actionRow(row1, {
		{ "💾 Overwrite", Theme.Accent,   function() overwrite()     end },
		{ "✨ Save New",  Theme.Success,  function() saveNew()       end },
	})

	local row2 = tab:_card(40, true)
	actionRow(row2, {
		{ "📂 Load",     Theme.AccentAlt, function() load()          end },
		{ "🗑 Delete",   Theme.Danger,    function() delete()        end },
		{ "↺ Defaults", Theme.Warning,   function() resetDefaults() end },
	})

	tab:AddSection("Auto-Load")
	tab:AddLabel("The last loaded/saved profile for each scope is restored automatically.")

	-- Initialise callbacks and auto-load game scope
	overwrite, saveNew, load, delete, resetDefaults =
		buildConfigUI(tab, Nova._cfg, selectorComp, nameInput)

	task.defer(function()
		local loaded = Nova._cfg:AutoLoad()
		if loaded then
			selectorComp:Set(loaded)
			Nova.Notify{ Title="Config", Text='Auto-loaded "'..loaded..'"', Type="info", Duration=2 }
		end
	end)
end



--------------------------------------------------------------------------------
-- Theme system  (color pickers, presets, game/global scope, save/load/delete)
--------------------------------------------------------------------------------
--[[
  Mount with:   themeTab:MountTheme()

  The GUI tab provides:
    • Toggle keybind picker (sets the window open/close key)
    • Game / Global scope toggle (Game = per-PlaceId, Global = shared)
    • Built-in preset buttons: Nova Dark, Midnight, Crimson, Ocean, Forest, Mono
    • Live color pickers for every Theme key (changes apply instantly)
    • Theme profile selector + name input
    • Save New, Overwrite, Load, Delete action buttons
    • Auto-loads the last used theme on startup for each scope
]]

local THEME_COLOR_KEYS = {
	"Background","Surface","SurfaceHover","Stroke",
	"Accent","AccentAlt","Text","SubText",
	"Success","Warning","Danger",
}

-- Built-in presets
local THEME_PRESETS = {
	["Nova Dark"] = {
		Background   = Color3.fromRGB(16, 16, 22),
		Surface      = Color3.fromRGB(26, 26, 36),
		SurfaceHover = Color3.fromRGB(38, 38, 54),
		Stroke       = Color3.fromRGB(52, 52, 72),
		Accent       = Color3.fromRGB(124, 92, 255),
		AccentAlt    = Color3.fromRGB(64, 170, 255),
		Text         = Color3.fromRGB(240, 240, 250),
		SubText      = Color3.fromRGB(145, 145, 170),
		Success      = Color3.fromRGB(70, 210, 140),
		Warning      = Color3.fromRGB(255, 190, 70),
		Danger       = Color3.fromRGB(255, 90, 105),
	},
	["Midnight"] = {
		Background   = Color3.fromRGB(8, 8, 14),
		Surface      = Color3.fromRGB(14, 14, 24),
		SurfaceHover = Color3.fromRGB(22, 22, 38),
		Stroke       = Color3.fromRGB(38, 38, 58),
		Accent       = Color3.fromRGB(90, 60, 220),
		AccentAlt    = Color3.fromRGB(40, 130, 220),
		Text         = Color3.fromRGB(220, 220, 240),
		SubText      = Color3.fromRGB(110, 110, 145),
		Success      = Color3.fromRGB(50, 185, 120),
		Warning      = Color3.fromRGB(220, 165, 50),
		Danger       = Color3.fromRGB(220, 70, 85),
	},
	["Crimson"] = {
		Background   = Color3.fromRGB(18, 10, 12),
		Surface      = Color3.fromRGB(30, 16, 20),
		SurfaceHover = Color3.fromRGB(46, 24, 30),
		Stroke       = Color3.fromRGB(70, 36, 44),
		Accent       = Color3.fromRGB(220, 50, 80),
		AccentAlt    = Color3.fromRGB(255, 120, 60),
		Text         = Color3.fromRGB(245, 230, 232),
		SubText      = Color3.fromRGB(170, 130, 140),
		Success      = Color3.fromRGB(65, 200, 130),
		Warning      = Color3.fromRGB(255, 185, 60),
		Danger       = Color3.fromRGB(255, 60, 80),
	},
	["Ocean"] = {
		Background   = Color3.fromRGB(8, 16, 26),
		Surface      = Color3.fromRGB(14, 26, 42),
		SurfaceHover = Color3.fromRGB(20, 40, 62),
		Stroke       = Color3.fromRGB(30, 58, 88),
		Accent       = Color3.fromRGB(40, 180, 255),
		AccentAlt    = Color3.fromRGB(60, 230, 200),
		Text         = Color3.fromRGB(220, 240, 255),
		SubText      = Color3.fromRGB(100, 150, 190),
		Success      = Color3.fromRGB(60, 210, 150),
		Warning      = Color3.fromRGB(255, 195, 60),
		Danger       = Color3.fromRGB(255, 80, 100),
	},
	["Forest"] = {
		Background   = Color3.fromRGB(10, 16, 12),
		Surface      = Color3.fromRGB(16, 26, 18),
		SurfaceHover = Color3.fromRGB(24, 40, 26),
		Stroke       = Color3.fromRGB(38, 60, 40),
		Accent       = Color3.fromRGB(80, 200, 100),
		AccentAlt    = Color3.fromRGB(160, 230, 80),
		Text         = Color3.fromRGB(225, 245, 228),
		SubText      = Color3.fromRGB(120, 160, 125),
		Success      = Color3.fromRGB(60, 210, 120),
		Warning      = Color3.fromRGB(220, 190, 60),
		Danger       = Color3.fromRGB(220, 80, 80),
	},
	["Mono"] = {
		Background   = Color3.fromRGB(12, 12, 12),
		Surface      = Color3.fromRGB(22, 22, 22),
		SurfaceHover = Color3.fromRGB(34, 34, 34),
		Stroke       = Color3.fromRGB(52, 52, 52),
		Accent       = Color3.fromRGB(200, 200, 200),
		AccentAlt    = Color3.fromRGB(160, 160, 160),
		Text         = Color3.fromRGB(240, 240, 240),
		SubText      = Color3.fromRGB(140, 140, 140),
		Success      = Color3.fromRGB(160, 200, 160),
		Warning      = Color3.fromRGB(200, 190, 140),
		Danger       = Color3.fromRGB(200, 140, 140),
	},
}
local PRESET_ORDER = { "Nova Dark","Midnight","Crimson","Ocean","Forest","Mono" }

local ThemeConfig = {}
ThemeConfig.__index = ThemeConfig
-- ThemeConfig.new is internal; use tab:MountTheme() for the GUI-driven workflow.

-- Auto-derived namespaces
local TNS_GAME   = "NovaTheme_" .. tostring(game.PlaceId)
local TNS_GLOBAL = "NovaTheme_Global"

local function _newThemeConfig(namespace)
	return setmetatable({
		_namespace     = namespace,
		_pickers       = {},
		_activeProfile = nil,
	}, ThemeConfig)
end

-- Two built-in instances
local _themeGame   = _newThemeConfig(TNS_GAME)
local _themeGlobal = _newThemeConfig(TNS_GLOBAL)
Nova._themeGame   = _themeGame
Nova._themeGlobal = _themeGlobal
Nova._theme       = _themeGame   -- active instance

-- ── internal helpers ──────────────────────────────────────────────────────────

function ThemeConfig:_getIndex()
	local raw = Storage.Load(self._namespace, "_index")
	if not raw then return {} end
	local ok, t = pcall(JSON.decode, raw)
	return (ok and type(t) == "table") and t or {}
end

function ThemeConfig:_setIndex(list)
	Storage.Save(self._namespace, "_index", JSON.encode(list))
end

function ThemeConfig:_profileExists(name)
	for _, n in self:_getIndex() do if n == name then return true end end
	return false
end

function ThemeConfig:_addToIndex(name)
	local idx = self:_getIndex()
	for _, n in idx do if n == name then return end end
	table.insert(idx, name); self:_setIndex(idx)
end

function ThemeConfig:_removeFromIndex(name)
	local idx = self:_getIndex()
	for i, n in idx do if n == name then table.remove(idx, i); break end end
	self:_setIndex(idx)
end

function ThemeConfig:_snapshot()
	local d = {}
	for _, key in THEME_COLOR_KEYS do
		local c = self._pickers[key] and self._pickers[key]:Get() or Theme[key]
		d[key] = { __type = "Color3", hex = colorToHex(c) }
	end
	return d
end

function ThemeConfig:_applyPalette(palette)
	local overrides = {}
	for _, key in THEME_COLOR_KEYS do
		local c = palette[key]
		if c and typeof(c) == "Color3" then
			if self._pickers[key] then self._pickers[key]:Set(c) end
			overrides[key] = c
		end
	end
	Nova.SetTheme(overrides)
	for k, v in overrides do Theme[k] = v end
end

-- ── public API ────────────────────────────────────────────────────────────────

function ThemeConfig:SaveProfile(name)
	name = (name ~= nil and tostring(name):match("^%s*(.-)%s*$")) or ""
	if name == "" then
		Nova.Notify{ Title="Theme", Text="Profile name cannot be empty.", Type="warning", Duration=3 }
		return false
	end
	Storage.Save(self._namespace, name, JSON.encode(self:_snapshot()))
	self:_addToIndex(name)
	self._activeProfile = name
	Storage.Save(self._namespace, "_active", JSON.encode(name))
	return true
end

function ThemeConfig:LoadProfile(name)
	local raw = Storage.Load(self._namespace, name)
	if not raw or raw == "" then
		Nova.Notify{ Title="Theme", Text='Profile "'..tostring(name)..'" not found.', Type="error", Duration=3 }
		return false
	end
	local ok, data = pcall(JSON.decode, raw)
	if not ok or type(data) ~= "table" then
		Nova.Notify{ Title="Theme", Text="Profile data corrupted.", Type="error", Duration=3 }
		return false
	end
	local palette = {}
	for k, v in data do
		local c = deserializeValue(v)
		if typeof(c) == "Color3" then palette[k] = c end
	end
	self:_applyPalette(palette)
	self._activeProfile = name
	Storage.Save(self._namespace, "_active", JSON.encode(name))
	return true
end

function ThemeConfig:DeleteProfile(name)
	Storage.Save(self._namespace, name, "")
	self:_removeFromIndex(name)
	if self._activeProfile == name then
		self._activeProfile = nil
		Storage.Save(self._namespace, "_active", JSON.encode(nil))
	end
end

function ThemeConfig:ApplyPreset(presetName)
	local palette = THEME_PRESETS[presetName]
	if not palette then return end
	self:_applyPalette(palette)
end

function ThemeConfig:AutoLoad()
	local raw = Storage.Load(self._namespace, "_active")
	if not raw then return nil end
	local ok, name = pcall(JSON.decode, raw)
	if not ok or type(name) ~= "string" or name == "" then return nil end
	if self:LoadProfile(name) then return name end
	return nil
end

-- ── tab UI ────────────────────────────────────────────────────────────────────

function Container:MountTheme()
	local tab    = self
	local window = self.Window

	-- ── Toggle Keybind ───────────────────────────────────────────────────────
	if window then
		tab:AddSection("Toggle Keybind")
		tab:AddLabel("Set the key used to open / close this window.")
		tab:AddKeybind{
			Text     = "Toggle Key",
			Default  = window._toggleKey or Enum.KeyCode.Unknown,
			Callback = function(key)
				window._toggleKey = key
				if window._toggleConn then
					window._toggleConn:Disconnect()
					window._toggleConn = nil
				end
				if key ~= Enum.KeyCode.Unknown then
					window._toggleConn = window:_connect(UserInputService.InputBegan,
						function(input, processed)
							if not processed and input.KeyCode == key then
								window:Toggle()
							end
						end)
				end
				Nova.Notify{
					Title = "Keybind",
					Text  = key == Enum.KeyCode.Unknown
						and "Toggle keybind cleared."
						or  'Toggle set to "'..key.Name..'"',
					Type  = "info", Duration = 2,
				}
			end,
		}
	end

	-- ── Game / Global toggle ─────────────────────────────────────────────────
	tab:AddSection("Theme Scope")

	local scopeRow = tab:_card(40, true)

	-- selector and name input declared before use in switchScope
	local selectorComp, nameInput

	local function refreshThemeUI(tc)
		Nova._theme = tc
		-- share pickers with both instances so snapshots always reflect live state
		_themeGame._pickers   = tc._pickers
		_themeGlobal._pickers = tc._pickers
		local idx = tc:_getIndex()
		selectorComp:SetOptions(idx)
		selectorComp:Set(idx[1])
		task.defer(function()
			local loaded = tc:AutoLoad()
			if loaded then
				selectorComp:Set(loaded)
				Nova.Notify{ Title="Theme", Text='Auto-loaded "'..loaded..'"', Type="info", Duration=2 }
			end
		end)
	end

	actionRow(scopeRow, {
		{ "🎮 Game",   Theme.Accent,    function() refreshThemeUI(_themeGame)   end },
		{ "🌐 Global", Theme.AccentAlt, function() refreshThemeUI(_themeGlobal) end },
	})

	-- ── Presets ──────────────────────────────────────────────────────────────
	tab:AddSection("Presets")
	tab:AddLabel("Click a preset to apply it instantly. You can then customise and save.")

	local presetsPerRow = 3
	for rowStart = 1, #PRESET_ORDER, presetsPerRow do
		local rowBtns = {}
		for i = rowStart, math.min(rowStart + presetsPerRow - 1, #PRESET_ORDER) do
			local pname = PRESET_ORDER[i]
			local accent = THEME_PRESETS[pname] and THEME_PRESETS[pname].Accent or Theme.Accent
			table.insert(rowBtns, { pname, accent, function()
				Nova._theme:ApplyPreset(pname)
				Nova.Notify{ Title="Theme", Text='Preset "'..pname..'" applied.', Type="info", Duration=2 }
			end })
		end
		local row = tab:_card(40, true)
		actionRow(row, rowBtns)
	end

	-- ── Color pickers (shared across both scopes) ─────────────────────────────
	tab:AddSection("Colors")
	local pickers = {}
	for _, key in THEME_COLOR_KEYS do
		local picker = tab:AddColorPicker{
			Text     = key,
			Default  = Theme[key] or Color3.new(1,1,1),
			Callback = function(c)
				Nova.SetTheme({ [key] = c })
				Theme[key] = c
			end,
		}
		pickers[key] = picker
	end
	-- give both instances the same picker table
	_themeGame._pickers   = pickers
	_themeGlobal._pickers = pickers

	-- ── Saved themes ─────────────────────────────────────────────────────────
	tab:AddSection("Saved Themes")

	local initIdx = _themeGame:_getIndex()
	selectorComp = tab:AddDropdown{
		Text    = "Active Theme",
		Options = initIdx,
		Default = initIdx[1],
	}

	nameInput = tab:AddTextInput{
		Text        = "Theme Name",
		Placeholder = "Enter name…",
	}

	local rowSave = tab:_card(40, true)
	actionRow(rowSave, {
		{ "💾 Overwrite", Theme.Accent, function()
			local sel = selectorComp:Get()
			if not sel then
				Nova.Notify{ Title="Theme", Text="Select a theme first.", Type="warning", Duration=3 }
				return
			end
			Nova.Dialog{
				Title   = 'Overwrite "'..tostring(sel)..'"?',
				Text    = "This will replace its saved colors.",
				Buttons = {
					{ Text = "Overwrite", Primary = true, Callback = function()
						if Nova._theme:SaveProfile(sel) then
							Nova.Notify{ Title="Theme", Text='Saved "'..sel..'"', Type="success", Duration=2 }
						end
					end },
					{ Text = "Cancel" },
				},
			}
		end },
		{ "✨ Save New", Theme.Success, function()
			local name = nameInput:Get():match("^%s*(.-)%s*$")
			if name == "" then
				Nova.Notify{ Title="Theme", Text="Type a name first.", Type="warning", Duration=3 }
				return
			end
			if Nova._theme:_profileExists(name) then
				Nova.Dialog{
					Title   = 'Theme "'..name..'" exists',
					Text    = "Overwrite it?",
					Buttons = {
						{ Text = "Overwrite", Primary = true, Callback = function()
							if Nova._theme:SaveProfile(name) then
								selectorComp:AddOption(name)
								selectorComp:Set(name)
								nameInput:Set("")
								Nova.Notify{ Title="Theme", Text='Saved "'..name..'"', Type="success", Duration=2 }
							end
						end },
						{ Text = "Cancel" },
					},
				}
			else
				if Nova._theme:SaveProfile(name) then
					selectorComp:AddOption(name)
					selectorComp:Set(name)
					nameInput:Set("")
					Nova.Notify{ Title="Theme", Text='Created "'..name..'"', Type="success", Duration=2 }
				end
			end
		end },
	})

	local rowLoad = tab:_card(40, true)
	actionRow(rowLoad, {
		{ "📂 Load", Theme.AccentAlt, function()
			local sel = selectorComp:Get()
			if not sel then
				Nova.Notify{ Title="Theme", Text="No theme selected.", Type="warning", Duration=3 }
				return
			end
			if Nova._theme:LoadProfile(sel) then
				Nova.Notify{ Title="Theme", Text='Loaded "'..sel..'"', Type="info", Duration=2 }
			end
		end },
		{ "🗑 Delete", Theme.Danger, function()
			local sel = selectorComp:Get()
			if not sel then
				Nova.Notify{ Title="Theme", Text="No theme selected.", Type="warning", Duration=3 }
				return
			end
			Nova.Dialog{
				Title   = 'Delete "'..tostring(sel)..'"?',
				Text    = "This cannot be undone.",
				Buttons = {
					{ Text = "Delete", Primary = true, Callback = function()
						Nova._theme:DeleteProfile(sel)
						selectorComp:RemoveOption(sel)
						Nova.Notify{ Title="Theme", Text='Deleted "'..sel..'"', Type="info", Duration=2 }
					end },
					{ Text = "Cancel" },
				},
			}
		end },
	})

	tab:AddSection("Auto-Load")
	tab:AddLabel("The last loaded/saved theme for each scope is restored automatically.")

	-- Initial auto-load (game scope)
	task.defer(function()
		local loaded = _themeGame:AutoLoad()
		if loaded then
			selectorComp:Set(loaded)
			Nova.Notify{ Title="Theme", Text='Auto-loaded "'..loaded..'"', Type="info", Duration=2 }
		end
	end)
end




--------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------

local Window = {}
Window.__index = Window

function Window:_connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(self._conns, c)
	return c
end

function Window:Open()
	if self.Opened then return end
	self.Opened = true
	self.Root.Visible = true
	A(self.Main,      "GroupTransparency", 0,                     P.Smooth)
	A(self.Main,      "Position",          UDim2.fromOffset(0, 0), P.Smooth)
	A(self.OpenScale, "Scale",             1,                      P.Bouncy)
end

function Window:Close()
	if not self.Opened then return end
	self.Opened = false
	A(self.Main,      "GroupTransparency", 1,                      P.Snappy)
	A(self.Main,      "Position",          UDim2.fromOffset(0, 24), P.Snappy)
	A(self.OpenScale, "Scale",             0.88,                    P.Snappy)
	task.delay(0.3, function()
		if not self.Opened and self.Root.Parent then self.Root.Visible = false end
	end)
end

function Window:Toggle()
	if self.Opened then self:Close() else self:Open() end
end

function Window:Minimize(state)
    if state == nil then state = not self.Minimized end
    self.Minimized = state
    local h = state and 46 or self.Size.Y
    A(self.Root, "Size", UDim2.fromOffset(self.Size.X, h), P.Smooth)
    if self.Sidebar then
        if state then
            -- hide immediately as the window collapses
            self.Sidebar.Visible = false
        else
            -- show before the expand animation plays
            self.Sidebar.Visible = true
        end
    end
end

-- Change the small text line shown under the player name in the sidebar.
-- Pass nil to restore the default (NovaUI version string).
function Window:SetStatusText(text)
	if self._statusLabel then
		self._statusLabel.Text = text ~= nil and tostring(text) or ("NovaUI " .. Nova.Version)
	end
end

function Window:SetTitle(title, subtitle)
	local sub = subtitle
		and ("  <font size=\"12\" color=\"" .. rgbString(Theme.SubText) .. "\">" .. subtitle .. "</font>")
		or  ""
	self.TitleLabel.Text = title .. sub
end

function Window:SelectTab(tab)
	if self.Current == tab then return end
	local old = self.Current
	self.Current = tab

	A(self.Indicator, "Position", UDim2.fromOffset(2, 10 + (tab.Index - 1) * 42 + 8), P.Bouncy)

	for _, t in self.Tabs do
		local active = t == tab
		A(t.Button, "BackgroundTransparency", active and 0  or 1,          P.Snappy)
		A(t.Button, "TextColor3",             active and Theme.Text or Theme.SubText, P.Snappy)
	end

	if old then
		A(old.Page, "GroupTransparency", 1,                      P.Snappy)
		A(old.Page, "Position",          UDim2.fromOffset(-24, 0), P.Snappy)
		task.delay(0.25, function()
			if self.Current ~= old then old.Page.Visible = false end
		end)
	end

	local page = tab.Page
	page.Visible = true
	Nova.Snap(page, "Position", UDim2.fromOffset(24, 0))
	A(page, "Position",          UDim2.fromOffset(0, 0), P.Smooth)
	A(page, "GroupTransparency", 0,                      P.Smooth)

	for i, sc in tab.Cards do
		Nova.Snap(sc, "Scale", 0.92)
		task.delay(math.min(i, 10) * 0.035, function()
			A(sc, "Scale", 1, P.Bouncy)
		end)
	end
end

function Window:AddTab(name, icon)
	local idx = #self.Tabs + 1
	local fullText = (icon and (icon .. "  ") or "") .. name
	local btn = create("TextButton", {
		Name             = name,
		Size             = UDim2.new(1, 0, 0, 36),
		LayoutOrder      = idx,
		BackgroundColor3 = Theme.SurfaceHover,
		BackgroundTransparency = 1,
		Text             = fullText,
		TextColor3       = Theme.SubText,
		TextXAlignment   = Enum.TextXAlignment.Left,
		TextTruncate     = Enum.TextTruncate.AtEnd,
		ClipsDescendants = true,
		Parent           = self.TabList,
	}, { corner(8), padding(14, 0, 8, 0) })
	-- Show full name in tooltip only when text is actually being clipped
	btn.MouseEnter:Connect(function()
		-- TextBounds.X > btn.AbsoluteSize.X - padding means it's clipped
		local textW = game:GetService("TextService"):GetTextSize(
			fullText, 14, Theme.Font, Vector2.new(9999, 9999)
		).X
		if textW > (btn.AbsoluteSize.X - 22) then
			showTooltip(name)
		end
	end)
	btn.MouseLeave:Connect(hideTooltip)

	local page = create("CanvasGroup", {
		Name             = name,
		Size             = UDim2.fromScale(1, 1),
		GroupTransparency= 1,
		Visible          = false,
		Parent           = self.Content,
	})
	local scroll = create("ScrollingFrame", {
		Size                  = UDim2.fromScale(1, 1),
		CanvasSize            = UDim2.new(),
		AutomaticCanvasSize   = Enum.AutomaticSize.Y,
		ScrollBarThickness    = 3,
		ScrollBarImageColor3  = Theme.Accent,
		ScrollingDirection    = Enum.ScrollingDirection.Y,
		Parent                = page,
	}, {
		create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
		padding(12, 12, 16, 12),
	})

	local tab = newContainer(self, scroll)
	tab.Button, tab.Page, tab.Index, tab.Name = btn, page, idx, name
	table.insert(self.Tabs, tab)

	btn.MouseEnter:Connect(function()
		if self.Current ~= tab then
			A(btn, "BackgroundTransparency", 0.6,        P.Snappy)
			A(btn, "TextColor3",             Theme.Text,  P.Snappy)
		end
	end)
	btn.MouseLeave:Connect(function()
		if self.Current ~= tab then
			A(btn, "BackgroundTransparency", 1,            P.Snappy)
			A(btn, "TextColor3",             Theme.SubText, P.Snappy)
		end
	end)
	btn.Activated:Connect(function() self:SelectTab(tab) end)

	if not self.Current then self:SelectTab(tab) end
	return tab
end

function Window:Destroy()
	for _, c in self._conns do c:Disconnect() end
	table.clear(self._conns)
	if self.OwnsGui then self.Gui:Destroy() else self.Root:Destroy() end
end

function Nova.Window(o)
	o = o or {}
	local self = setmetatable({ _conns = {}, Tabs = {}, Opened = false, Minimized = false }, Window)
	local size = o.Size or Vector2.new(580, 400)
	self.Size = size
	self.OwnsGui = o.Gui == nil
	self.Gui = o.Gui or Nova.ScreenGui(o.Name or "NovaWindow")

	local root = create("Frame", {
		Name        = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position    = UDim2.fromScale(0.5, 0.5),
		Size        = UDim2.fromOffset(size.X, size.Y),
		Visible     = false,
		Parent      = self.Gui,
	})
	local fit = create("UIScale", { Parent = root })
	self.Root = root

	local function refit()
		local cam = workspace.CurrentCamera
		if cam then
			local vp = cam.ViewportSize
			fit.Scale = math.min(1, (vp.X - 24) / size.X, (vp.Y - 24) / size.Y)
		end
	end
	refit()
	if workspace.CurrentCamera then
		self:_connect(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), refit)
	end

	local main = create("CanvasGroup", {
		Name             = "Main",
		Size             = UDim2.fromScale(1, 1),
		Position         = UDim2.fromOffset(0, 24),
		BackgroundColor3 = Theme.Background,
		GroupTransparency= 1,
		Parent           = root,
	}, { corner(14) })
	self.Main = main
	self.OpenScale = create("UIScale", { Scale = 0.88, Parent = main })

	local border = stroke(Theme.Accent, 1.5, 0.3)
	border.Parent = main
	local borderGrad = create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0,   Theme.Accent),
			ColorSequenceKeypoint.new(0.5, Theme.AccentAlt),
			ColorSequenceKeypoint.new(1,   Theme.Accent),
		}),
		Parent = border,
	})
	self:_connect(RunService.RenderStepped, function()
		if self.Opened then borderGrad.Rotation = (os.clock() * 45) % 360 end
	end)

	local top = create("Frame", {
		Name             = "TopBar",
		Size             = UDim2.new(1, 0, 0, 46),
		BackgroundColor3 = Theme.Surface,
		Parent           = main,
	})
	create("Frame", {
		AnchorPoint      = Vector2.new(0, 1),
		Position         = UDim2.fromScale(0, 1),
		Size             = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = Theme.Stroke,
		Parent           = top,
	})
	self.TitleLabel = create("TextLabel", {
		Position       = UDim2.fromOffset(16, 0),
		Size           = UDim2.new(1, -110, 1, 0),
		Font           = Theme.FontBold,
		TextSize       = 16,
		RichText       = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent         = top,
	})
	self:SetTitle(o.Title or "Nova UI", o.Subtitle)

	local function ctrl(text, xOff, hoverColor, cb)
		local b = create("TextButton", {
			AnchorPoint      = Vector2.new(1, 0.5),
			Position         = UDim2.new(1, xOff, 0.5, 0),
			Size             = UDim2.fromOffset(28, 28),
			BackgroundColor3 = Theme.SurfaceHover,
			BackgroundTransparency = 1,
			Text             = text,
			Font             = Theme.FontBold,
			TextSize         = 16,
			TextColor3       = Theme.SubText,
			Parent           = top,
		}, { corner(8) })
		local s = create("UIScale", { Parent = b })
		b.MouseEnter:Connect(function()
			A(b, "BackgroundTransparency", 0,          P.Snappy)
			A(b, "TextColor3",             hoverColor,  P.Snappy)
			A(s, "Scale",                  1.1,         P.Bouncy)
		end)
		b.MouseLeave:Connect(function()
			A(b, "BackgroundTransparency", 1,             P.Snappy)
			A(b, "TextColor3",             Theme.SubText,  P.Snappy)
			A(s, "Scale",                  1,              P.Snappy)
		end)
		b.MouseButton1Down:Connect(function() A(s, "Scale", 0.88, P.Snappy) end)
		b.Activated:Connect(cb)
	end
	ctrl("×", -12, Theme.Danger,   function() self:Close() end)
	ctrl("–", -46, Theme.Warning,  function() self:Minimize() end)

	local sidebar = create("Frame", {
		Name   = "Sidebar",
		Position = UDim2.fromOffset(0, 46),
		Size     = UDim2.new(0, 150, 1, -46),
		Parent   = main,
	})
	create("Frame", {
		AnchorPoint      = Vector2.new(1, 0),
		Position         = UDim2.fromScale(1, 0),
		Size             = UDim2.new(0, 1, 1, 0),
		BackgroundColor3 = Theme.Stroke,
		Parent           = sidebar,
	})
	self.TabList = create("Frame", { Size = UDim2.fromScale(1, 1), Parent = sidebar }, {
		create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		padding(8, 10, 8, 8),
	})
	self.Indicator = create("Frame", {
		Position         = UDim2.fromOffset(2, 18),
		Size             = UDim2.fromOffset(3, 20),
		BackgroundColor3 = Theme.Accent,
		ZIndex           = 3,
		Parent           = sidebar,
	}, { pill() })
	self.Sidebar = sidebar

	self.Content = create("Frame", {
		Name     = "Content",
		Position = UDim2.fromOffset(150, 46),
		Size     = UDim2.new(1, -150, 1, -46),
		Parent   = main,
	})

	-- ── Player profile card (bottom-right of sidebar) ───────────────────────
	-- Height: 64px card pinned to the bottom of the sidebar
	local PROFILE_H = 68
	local profileCard = create("Frame", {
		Name             = "ProfileCard",
		AnchorPoint      = Vector2.new(0, 1),
		Position         = UDim2.new(0, 0, 1, 0),
		Size             = UDim2.new(1, 0, 0, PROFILE_H),
		BackgroundColor3 = Theme.Background,
		ZIndex           = 2,
		Parent           = sidebar,
	})
	-- top divider
	create("Frame", {
		Size             = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = Theme.Stroke,
		ZIndex           = 3,
		Parent           = profileCard,
	})

	-- Avatar image (36×36, pill)
	local avatarImg = create("ImageLabel", {
		AnchorPoint      = Vector2.new(0, 0.5),
		Position         = UDim2.new(0, 10, 0.5, -6),   -- shift up a little for status text
		Size             = UDim2.fromOffset(34, 34),
		BackgroundColor3 = Theme.Surface,
		ZIndex           = 3,
		Parent           = profileCard,
	}, { pill(), stroke(Theme.Stroke, 1, 0.3) })

	-- Display name label
	local displayNameLabel = create("TextLabel", {
		Position         = UDim2.new(0, 50, 0, 8),
		Size             = UDim2.new(1, -54, 0, 18),
		Text             = "…",
		Font             = Theme.FontBold,
		TextSize         = 12,
		TextColor3       = Theme.Text,
		TextXAlignment   = Enum.TextXAlignment.Left,
		TextTruncate     = Enum.TextTruncate.AtEnd,
		ZIndex           = 3,
		Parent           = profileCard,
	})

	-- Status / custom text label  (win:SetStatusText changes this)
	local statusLabel = create("TextLabel", {
		Position         = UDim2.new(0, 50, 0, 28),
		Size             = UDim2.new(1, -54, 0, 14),
		Text             = o.StatusText or "NovaUI " .. Nova.Version,
		Font             = Theme.Font,
		TextSize         = 11,
		TextColor3       = Theme.SubText,
		TextXAlignment   = Enum.TextXAlignment.Left,
		TextTruncate     = Enum.TextTruncate.AtEnd,
		ZIndex           = 3,
		Parent           = profileCard,
	})
	self._statusLabel = statusLabel

	-- Tooltip hit area – shows Username + UserId
	local profileHit = create("TextButton", {
		Size   = UDim2.fromScale(1, 1),
		ZIndex = 4,
		Parent = profileCard,
	})

	-- Load avatar + fill labels asynchronously
	task.spawn(function()
		local lp = Players.LocalPlayer
		if not lp then return end

		-- Display name
		local ok1, dn = pcall(function() return lp.DisplayName end)
		displayNameLabel.Text = (ok1 and dn) or lp.Name

		-- Tooltip
		local uid = lp.UserId
		local tooltipText = "@" .. lp.Name .. "  •  ID: " .. tostring(uid)
		profileHit.MouseEnter:Connect(function() showTooltip(tooltipText) end)
		profileHit.MouseLeave:Connect(hideTooltip)

		-- Avatar thumbnail
		local ok2, url = pcall(function()
			return Players:GetUserThumbnailAsync(uid,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size48x48)
		end)
		if ok2 and url then avatarImg.Image = url end
	end)

	-- Shrink TabList so it doesn't overlap the profile card
	-- We resize it to leave PROFILE_H px at the bottom
	self.TabList.Size = UDim2.new(1, 0, 1, -PROFILE_H)

	local dragging, dragStart, startPos = false, nil, nil
	top.InputBegan:Connect(function(input)
		if isPress(input) then
			dragging, dragStart, startPos = true, input.Position, root.Position
		end
	end)
	self:_connect(UserInputService.InputChanged, function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
		              or input.UserInputType == Enum.UserInputType.Touch) then
			local d = (input.Position - dragStart) / fit.Scale
			Nova.Animate(root, "Position",
				UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
				          startPos.Y.Scale, startPos.Y.Offset + d.Y),
				40, 1)
		end
	end)
	self:_connect(UserInputService.InputEnded, function(input)
		if isPress(input) then dragging = false end
	end)

	if o.ToggleKey then
		self._toggleKey  = o.ToggleKey
		self._toggleConn = self:_connect(UserInputService.InputBegan, function(input, processed)
			if not processed and input.KeyCode == self._toggleKey then self:Toggle() end
		end)
	else
		self._toggleKey  = Enum.KeyCode.Unknown
		self._toggleConn = nil
	end

	if not o.StartHidden then
		task.defer(function() self:Open() end)
	end
	return self
end

--------------------------------------------------------------------------------
-- Notifications (toasts)
--------------------------------------------------------------------------------

local holder
local toastId = 0

local function getHolder()
	if holder and holder.Parent then return holder end
	local gui = Nova.ScreenGui("NovaNotifications", 1000)
	holder = create("Frame", {
		AnchorPoint = Vector2.new(1, 1),
		Position    = UDim2.new(1, -14, 1, -14),
		Size        = UDim2.new(0, 320, 1, -28),
		Parent      = gui,
	}, {
		create("UIListLayout", {
			Padding           = UDim.new(0, 8),
			SortOrder         = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
		}),
	})
	return holder
end

function Nova.Notify(o)
	o = o or {}
	local kinds    = { info = Theme.Accent, success = Theme.Success, warning = Theme.Warning, error = Theme.Danger }
	local color    = kinds[o.Type or "info"] or Theme.Accent
	local duration = o.Duration or 4
	local H = 72
	toastId += 1

	local wrap = create("Frame", { Size = UDim2.new(1, 0, 0, 0), LayoutOrder = toastId, Parent = getHolder() })
	local card = create("CanvasGroup", {
		Size             = UDim2.new(1, 0, 0, H),
		Position         = UDim2.fromOffset(340, 0),
		BackgroundColor3 = Theme.Surface,
		GroupTransparency= 1,
		Parent           = wrap,
	}, { corner(10), stroke(Theme.Stroke, 1, 0.2) })

	create("Frame", { Size = UDim2.new(0, 4, 1, 0), BackgroundColor3 = color, Parent = card })
	create("TextLabel", {
		Position = UDim2.fromOffset(18, 9), Size = UDim2.new(1, -30, 0, 18),
		Text = o.Title or "Notification", Font = Theme.FontBold, TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left, Parent = card,
	})
	create("TextLabel", {
		Position = UDim2.fromOffset(18, 28), Size = UDim2.new(1, -30, 0, 34),
		Text = o.Text or "", TextSize = 13, TextColor3 = Theme.SubText,
		TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		Parent = card,
	})
	local bar = create("Frame", {
		AnchorPoint      = Vector2.new(0, 1),
		Position         = UDim2.fromScale(0, 1),
		Size             = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = color,
		Parent           = card,
	})
	local hit = create("TextButton", { Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = card })

	local closed = false
	local function dismiss()
		if closed then return end
		closed = true
		A(card, "Position",          UDim2.fromOffset(340, 0), P.Snappy)
		A(card, "GroupTransparency", 1,                        P.Snappy)
		task.delay(0.12, function()
			if wrap.Parent then A(wrap, "Size", UDim2.new(1, 0, 0, 0), P.Smooth) end
		end)
		task.delay(0.7, function() wrap:Destroy() end)
	end

	A(wrap, "Size",             UDim2.new(1, 0, 0, H), P.Bouncy)
	A(card, "Position",          UDim2.fromOffset(0, 0),  P.Bouncy)
	A(card, "GroupTransparency", 0,                        P.Smooth)

	TweenService:Create(bar, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 0, 2) }):Play()
	task.delay(duration, dismiss)
	hit.Activated:Connect(dismiss)

	return { Dismiss = dismiss }
end

--------------------------------------------------------------------------------
-- Dialog (modal)
--------------------------------------------------------------------------------

function Nova.Dialog(o)
	o = o or {}
	local gui = Nova.ScreenGui("NovaDialog", 900)

	local dim = create("TextButton", {
		Size             = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Parent           = gui,
	})
	local card = create("CanvasGroup", {
		AnchorPoint      = Vector2.new(0.5, 0.5),
		Position         = UDim2.fromScale(0.5, 0.5),
		Size             = UDim2.fromOffset(340, 0),
		AutomaticSize    = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Surface,
		GroupTransparency= 1,
		Parent           = gui,
	}, {
		corner(14),
		stroke(Theme.Stroke, 1, 0.2),
		create("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
		padding(18, 18, 18, 18),
	})
	local sc = create("UIScale", { Scale = 0.8, Parent = card })

	create("TextLabel", {
		LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 24),
		Text = o.Title or "Dialog", Font = Theme.FontBold, TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left, Parent = card,
	})
	create("TextLabel", {
		LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		Text = o.Text or "", TextColor3 = Theme.SubText, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		Parent = card,
	})
	local row = create("Frame", { LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 38), Parent = card }, {
		create("UIListLayout", {
			FillDirection        = Enum.FillDirection.Horizontal,
			HorizontalAlignment  = Enum.HorizontalAlignment.Right,
			VerticalAlignment    = Enum.VerticalAlignment.Center,
			Padding              = UDim.new(0, 8),
		}),
	})

	local closing = false
	local function close()
		if closing then return end
		closing = true
		A(dim,  "BackgroundTransparency", 1,    P.Smooth)
		A(card, "GroupTransparency",      1,    P.Snappy)
		A(sc,   "Scale",                  0.9,  P.Snappy)
		task.delay(0.4, function() gui:Destroy() end)
	end

	for i, b in o.Buttons or { { Text = "OK", Primary = true } } do
		local base  = b.Primary and Theme.Accent or Theme.SurfaceHover
		local hover = b.Primary and Theme.AccentAlt or Theme.Stroke
		local btn   = create("TextButton", {
			LayoutOrder      = i,
			Size             = UDim2.fromOffset(96, 34),
			BackgroundColor3 = base,
			Text             = b.Text or "OK",
			Font             = Theme.FontBold,
			Parent           = row,
		}, { corner(8) })
		local s = create("UIScale", { Parent = btn })
		hoverable(btn, btn, s, base, hover, 1.05)
		btn.Activated:Connect(function()
			close()
			if b.Callback then task.spawn(b.Callback) end
		end)
	end

	if o.Dismissible ~= false then dim.Activated:Connect(close) end

	A(dim,  "BackgroundTransparency", 0.45, P.Smooth)
	A(card, "GroupTransparency",      0,    P.Smooth)
	A(sc,   "Scale",                  1,    P.Bouncy)

	return { Close = close }
end

return Nova

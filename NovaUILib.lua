--!nonstrict
--[[
	NovaUI v1.0 | modern, spring-animated UI library for Roblox (client-side)

	Install: put this in a ModuleScript named "NovaUI" (ReplicatedStorage works well)
	and require it from a LocalScript. See Example.client.lua.

	Features
	  * Spring physics engine (interruptible, bouncy, no tween snapping)
	  * Window: draggable, minimize, open/close animations, rotating gradient border,
	    animated tab sidebar, staggered content reveal, toggle keybind
	  * Components: Button (ripple), Toggle, Slider, TextInput, Dropdown,
	    Label, Section, ProgressBar
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
	  tab:AddLabel("Some text") ; tab:AddSection("Header") ; tab:AddProgress{ Text = "XP", Value = 0.4 }
	  Nova.Notify{ Title = "Saved", Text = "Done!", Type = "success", Duration = 4 }
	  Nova.Dialog{ Title = "Sure?", Text = "...", Buttons = { { Text = "Yes", Primary = true } } }
	  Nova.Animate(anyGuiObject, "Size", UDim2.fromOffset(200, 50), 24, 0.6) -- spring anything
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local Nova = {}
Nova.Version = "1.0.0"

--------------------------------------------------------------------------------
-- Theme
--------------------------------------------------------------------------------

Nova.Theme = {
	Background = Color3.fromRGB(16, 16, 22),
	Surface = Color3.fromRGB(26, 26, 36),
	SurfaceHover = Color3.fromRGB(38, 38, 54),
	Stroke = Color3.fromRGB(52, 52, 72),
	Accent = Color3.fromRGB(124, 92, 255),
	AccentAlt = Color3.fromRGB(64, 170, 255),
	Text = Color3.fromRGB(240, 240, 250),
	SubText = Color3.fromRGB(145, 145, 170),
	Success = Color3.fromRGB(70, 210, 140),
	Warning = Color3.fromRGB(255, 190, 70),
	Danger = Color3.fromRGB(255, 90, 105),
	Font = Enum.Font.GothamMedium,
	FontBold = Enum.Font.GothamBold,
}
local Theme = Nova.Theme

-- Call BEFORE building any UI. Example: Nova.SetTheme({ Accent = Color3.fromRGB(255, 80, 120) })
function Nova.SetTheme(overrides)
	for k, v in overrides do
		Theme[k] = v
	end
end

--------------------------------------------------------------------------------
-- Spring engine
--------------------------------------------------------------------------------

-- { speed (rad/s, higher = faster), damping (1 = no overshoot, <1 = bouncy) }
local P = {
	Snappy = { 32, 1 },
	Smooth = { 16, 1 },
	Bouncy = { 24, 0.55 },
	Wobbly = { 14, 0.38 },
}
Nova.Presets = P

local Springs = {} -- [instance] = { [property] = state }
local Tracked = setmetatable({}, { __mode = "k" })
local stepConn

local function encode(v)
	local t = typeof(v)
	if t == "number" then
		return { v }
	elseif t == "Color3" then
		return { v.R, v.G, v.B }
	elseif t == "UDim2" then
		return { v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset }
	elseif t == "Vector2" then
		return { v.X, v.Y }
	elseif t == "UDim" then
		return { v.Scale, v.Offset }
	end
	error("NovaUI: cannot animate value of type " .. t)
end

local function decode(kind, a, prop)
	if kind == "number" then
		if string.find(prop, "Transparency") then
			return math.clamp(a[1], 0, 1)
		end
		return a[1]
	elseif kind == "Color3" then
		return Color3.new(math.clamp(a[1], 0, 1), math.clamp(a[2], 0, 1), math.clamp(a[3], 0, 1))
	elseif kind == "UDim2" then
		return UDim2.new(a[1], a[2], a[3], a[4])
	elseif kind == "Vector2" then
		return Vector2.new(a[1], a[2])
	elseif kind == "UDim" then
		return UDim.new(a[1], a[2])
	end
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
				if math.abs(p - t) > 0.001 or math.abs(v) > 0.01 then
					settled = false
				end
				pos[i], vel[i] = p, v
			end

			if settled then
				for i = 1, #pos do
					pos[i], vel[i] = tgt[i], 0
				end
				props[prop] = nil
			end
			inst[prop] = decode(s.kind, pos, prop)
		end
		if next(props) == nil then
			Springs[inst] = nil
		end
	end

	if next(Springs) == nil and stepConn then
		stepConn:Disconnect()
		stepConn = nil
	end
end

-- Spring any Color3 / number / UDim / UDim2 / Vector2 property toward a target.
-- speed can also be a preset table, e.g. Nova.Presets.Bouncy
function Nova.Animate(inst, prop, target, speed, damping)
	if type(speed) == "table" then
		speed, damping = speed[1], speed[2]
	end
	local kind = typeof(target)
	local props = Springs[inst]
	if not props then
		props = {}
		Springs[inst] = props
		if not Tracked[inst] then
			Tracked[inst] = true
			inst.Destroying:Once(function()
				Springs[inst] = nil
			end)
		end
	end

	local tgt = encode(target)
	local s = props[prop]
	if s and s.kind == kind then
		-- interrupt smoothly: keep position AND velocity
		s.tgt = tgt
		s.speed = speed or s.speed
		s.damping = damping or s.damping
	else
		local cur = encode(inst[prop])
		props[prop] = {
			kind = kind,
			pos = cur,
			vel = table.create(#cur, 0),
			tgt = tgt,
			speed = speed or 22,
			damping = damping or 0.9,
		}
	end

	if not stepConn then
		stepConn = RunService.RenderStepped:Connect(stepAll)
	end
end

-- Instantly set a property and cancel any running spring on it.
function Nova.Snap(inst, prop, value)
	local props = Springs[inst]
	if props then
		props[prop] = nil
	end
	inst[prop] = value
end

local function A(inst, prop, target, preset)
	preset = preset or P.Smooth
	Nova.Animate(inst, prop, target, preset[1], preset[2])
end

local function put(inst, prop, value, preset, instant)
	if instant then
		Nova.Snap(inst, prop, value)
	else
		A(inst, prop, value, preset)
	end
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
	if inst:IsA("GuiButton") then
		inst.AutoButtonColor = false
	end
	if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
		inst.Text = ""
		inst.Font = Theme.Font
		inst.TextColor3 = Theme.Text
		inst.TextSize = 14
	end
	if props then
		if props.BackgroundColor3 and props.BackgroundTransparency == nil then
			inst.BackgroundTransparency = 0
		end
		for k, v in props do
			if k ~= "Parent" then
				inst[k] = v
			end
		end
	end
	if children then
		for _, c in children do
			c.Parent = inst
		end
	end
	if props and props.Parent then
		inst.Parent = props.Parent
	end
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
		Color = color,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

local function padding(l, t, r, b)
	return create("UIPadding", {
		PaddingLeft = UDim.new(0, l),
		PaddingTop = UDim.new(0, t),
		PaddingRight = UDim.new(0, r),
		PaddingBottom = UDim.new(0, b),
	})
end

local function rgbString(c)
	return string.format(
		"rgb(%d,%d,%d)",
		math.floor(c.R * 255 + 0.5),
		math.floor(c.G * 255 + 0.5),
		math.floor(c.B * 255 + 0.5)
	)
end

local function fmt(v)
	return tostring(math.round(v * 1000) / 1000)
end

local function isPress(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

-- Standard hover / press feel for a button with its own UIScale
local function hoverable(btn, target, scaleObj, normalColor, hoverColor, hoverScale)
	hoverScale = hoverScale or 1.02
	btn.MouseEnter:Connect(function()
		if hoverColor then
			A(target, "BackgroundColor3", hoverColor, P.Snappy)
		end
		A(scaleObj, "Scale", hoverScale, P.Bouncy)
	end)
	btn.MouseLeave:Connect(function()
		if normalColor then
			A(target, "BackgroundColor3", normalColor, P.Snappy)
		end
		A(scaleObj, "Scale", 1, P.Snappy)
	end)
	btn.MouseButton1Down:Connect(function()
		A(scaleObj, "Scale", 0.96, P.Snappy)
	end)
	btn.MouseButton1Up:Connect(function()
		A(scaleObj, "Scale", hoverScale, P.Bouncy)
	end)
end

-- Expanding circle ripple at the pointer (parent must be a CanvasGroup so corners clip it)
local function ripple(face, input)
	local point = Vector2.new(input.Position.X, input.Position.Y) + GuiService:GetGuiInset()
	local rel = (point - face.AbsolutePosition) / face.AbsoluteSize
	local r = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(math.clamp(rel.X, 0, 1), math.clamp(rel.Y, 0, 1)),
		Size = UDim2.fromScale(0, 0),
		SizeConstraint = Enum.SizeConstraint.RelativeXX,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.72,
		ZIndex = 2,
		Parent = face,
	}, { pill() })
	A(r, "Size", UDim2.fromScale(2.6, 2.6), { 12, 1 })
	A(r, "BackgroundTransparency", 1, { 9, 1 })
	task.delay(0.8, function()
		r:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- ScreenGui factory
--------------------------------------------------------------------------------

function Nova.ScreenGui(name, displayOrder)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	return create("ScreenGui", {
		Name = name or "NovaUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = displayOrder or 10,
		Parent = playerGui,
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
		Size = UDim2.new(1, 0, 0, height),
		LayoutOrder = self._order,
		BackgroundColor3 = if bare then nil else Theme.Surface,
		Parent = self.Scroll,
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
		A(card, "BackgroundColor3", Theme.SurfaceHover, P.Snappy)
		A(scale, "Scale", 1.01, P.Bouncy)
	end)
	hit.MouseLeave:Connect(function()
		A(card, "BackgroundColor3", Theme.Surface, P.Snappy)
		A(scale, "Scale", 1, P.Snappy)
	end)
end

function Container:AddSection(text)
	local card = self:_card(26, true)
	create("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		Text = string.upper(text or "Section"),
		Font = Theme.FontBold,
		TextSize = 11,
		TextColor3 = Theme.Accent,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		Parent = card,
	}, { padding(4, 0, 0, 2) })
	return { Frame = card }
end

function Container:AddLabel(text)
	local card = self:_card(0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	padding(14, 11, 14, 11).Parent = card
	local lbl = create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = text or "",
		TextColor3 = Theme.SubText,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = card,
	})
	return {
		Frame = card,
		Set = function(_, t)
			lbl.Text = t
		end,
	}
end

function Container:AddButton(o)
	o = o or {}
	local card, scale = self:_card(40, true)

	local grad = create("UIGradient", {
		Color = ColorSequence.new(Theme.Accent, Theme.AccentAlt),
		Rotation = 20,
	})
	local face = create("CanvasGroup", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = card,
	}, { corner(8), grad })
	local label = create("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		Text = o.Text or "Button",
		Font = Theme.FontBold,
		TextColor3 = Color3.new(1, 1, 1),
		ZIndex = 4,
		Parent = card,
	})
	local hit = create("TextButton", { Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = card })

	hit.MouseEnter:Connect(function()
		A(scale, "Scale", 1.02, P.Bouncy)
		A(grad, "Rotation", 110, { 10, 1 })
	end)
	hit.MouseLeave:Connect(function()
		A(scale, "Scale", 1, P.Snappy)
		A(grad, "Rotation", 20, { 10, 1 })
	end)
	hit.MouseButton1Down:Connect(function()
		A(scale, "Scale", 0.96, P.Snappy)
	end)
	hit.MouseButton1Up:Connect(function()
		A(scale, "Scale", 1.02, P.Bouncy)
	end)
	hit.InputBegan:Connect(function(input)
		if isPress(input) then
			ripple(face, input)
		end
	end)
	hit.Activated:Connect(function()
		if o.Callback then
			task.spawn(o.Callback)
		end
	end)

	return {
		Frame = card,
		SetText = function(_, t)
			label.Text = t
		end,
	}
end

function Container:AddToggle(o)
	o = o or {}
	local card, scale = self:_card(44)
	create("TextLabel", {
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -80, 1, 0),
		Text = o.Text or "Toggle",
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	local track = create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0),
		Size = UDim2.fromOffset(44, 24),
		BackgroundColor3 = Theme.Stroke,
		Parent = card,
	}, { pill() })
	local knob = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 3, 0.5, 0),
		Size = UDim2.fromOffset(18, 18),
		BackgroundColor3 = Theme.Text,
		Parent = track,
	}, { pill() })
	local hit = create("TextButton", { Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = card })

	local state = o.Default == true
	local pressed = false

	local function render(instant)
		local w = pressed and 24 or 18
		local x = state and (44 - 3 - w) or 3
		put(knob, "Size", UDim2.fromOffset(w, 18), P.Snappy, instant)
		put(knob, "Position", UDim2.new(0, x, 0.5, 0), P.Bouncy, instant)
		put(track, "BackgroundColor3", state and Theme.Accent or Theme.Stroke, P.Snappy, instant)
	end
	render(true)

	local function set(v, fire)
		state = v
		render(false)
		if fire and o.Callback then
			task.spawn(o.Callback, state)
		end
	end

	cardHover(card, hit, scale)
	hit.MouseButton1Down:Connect(function()
		pressed = true
		render(false)
	end)
	local function release()
		if pressed then
			pressed = false
			render(false)
		end
	end
	hit.MouseButton1Up:Connect(release)
	hit.MouseLeave:Connect(release)
	hit.Activated:Connect(function()
		set(not state, true)
	end)

	return {
		Frame = card,
		Get = function()
			return state
		end,
		Set = function(_, v)
			set(v == true, true)
		end,
	}
end

function Container:AddSlider(o)
	o = o or {}
	local min, max, inc = o.Min or 0, o.Max or 100, o.Increment or 1
	local suffix = o.Suffix or ""
	local value = math.clamp(o.Default or min, min, max)
	local card, scale = self:_card(58)

	create("TextLabel", {
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.new(1, -100, 0, 18),
		Text = o.Text or "Slider",
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	local valueLabel = create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 8),
		Size = UDim2.fromOffset(80, 18),
		Font = Theme.FontBold,
		TextColor3 = Theme.Accent,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = card,
	})
	local track = create("Frame", {
		Position = UDim2.new(0, 14, 0, 38),
		Size = UDim2.new(1, -28, 0, 6),
		BackgroundColor3 = Theme.Stroke,
		Parent = card,
	}, { pill() })
	local fill = create("Frame", {
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Parent = track,
	}, { pill(), create("UIGradient", { Color = ColorSequence.new(Theme.Accent, Theme.AccentAlt) }) })
	local knob = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 3,
		Parent = fill,
	}, { pill(), stroke(Theme.Accent, 2, 0) })
	local hit = create("TextButton", {
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.new(1, 0, 0, 36),
		ZIndex = 5,
		Parent = card,
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
			if o.Callback then
				task.spawn(o.Callback, v)
			end
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
		if
			dragging
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
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
		Get = function()
			return value
		end,
		Set = function(_, v)
			setValue(v, true)
		end,
	}
end

function Container:AddTextInput(o)
	o = o or {}
	local card, scale = self:_card(44)
	create("TextLabel", {
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -200, 1, 0),
		Text = o.Text or "Input",
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	local box = create("TextBox", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(170, 28),
		BackgroundColor3 = Theme.Background,
		Text = o.Default or "",
		PlaceholderText = o.Placeholder or "",
		PlaceholderColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		ClipsDescendants = true,
		Parent = card,
	}, { corner(6), padding(10, 0, 10, 0) })
	local border = stroke(Theme.Stroke, 1, 0)
	border.Parent = box
	local boxScale = create("UIScale", { Parent = box })

	box.Focused:Connect(function()
		A(border, "Color", Theme.Accent, P.Snappy)
		A(border, "Thickness", 2, P.Snappy)
		A(boxScale, "Scale", 1.04, P.Bouncy)
	end)
	box.FocusLost:Connect(function(enter)
		A(border, "Color", Theme.Stroke, P.Snappy)
		A(border, "Thickness", 1, P.Snappy)
		A(boxScale, "Scale", 1, P.Snappy)
		if o.Callback then
			task.spawn(o.Callback, box.Text, enter)
		end
	end)
	box.MouseEnter:Connect(function()
		A(scale, "Scale", 1.01, P.Bouncy)
	end)
	box.MouseLeave:Connect(function()
		A(scale, "Scale", 1, P.Snappy)
	end)

	return {
		Frame = card,
		Get = function()
			return box.Text
		end,
		Set = function(_, t)
			box.Text = t
		end,
	}
end

function Container:AddDropdown(o)
	o = o or {}
	local options = o.Options or {}
	local selected = o.Default
	local HEAD, OPT = 44, 30
	local card, scale = self:_card(HEAD)
	card.ClipsDescendants = true

	create("TextLabel", {
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(0.5, -14, 0, HEAD),
		Text = o.Text or "Dropdown",
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	local valueLabel = create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -36, 0, 0),
		Size = UDim2.new(0.5, -36, 0, HEAD),
		Text = selected ~= nil and tostring(selected) or "Select…",
		TextColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = card,
	})
	local chevron = create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 0),
		Size = UDim2.fromOffset(18, HEAD),
		Text = "▾",
		TextSize = 16,
		TextColor3 = Theme.SubText,
		Parent = card,
	})
	local list = create("ScrollingFrame", {
		Position = UDim2.fromOffset(8, HEAD),
		Size = UDim2.new(1, -16, 0, 0),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 2,
		ScrollBarImageColor3 = Theme.Accent,
		Parent = card,
	}, { create("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }) })
	local hit = create("TextButton", { Size = UDim2.new(1, 0, 0, HEAD), ZIndex = 5, Parent = card })

	local open = false
	local buttons = {}

	local function listHeight()
		return math.min(#options * (OPT + 2), 150)
	end

	local function setOpen(v)
		open = v
		A(card, "Size", UDim2.new(1, 0, 0, v and (HEAD + listHeight() + 8) or HEAD), P.Snappy)
		A(chevron, "Rotation", v and 180 or 0, P.Bouncy)
		A(chevron, "TextColor3", v and Theme.Accent or Theme.SubText, P.Snappy)
	end

	local function choose(opt, fire)
		selected = opt
		valueLabel.Text = tostring(opt)
		for _, b in buttons do
			A(b, "TextColor3", b.Name == tostring(opt) and Theme.Accent or Theme.Text, P.Snappy)
		end
		if fire and o.Callback then
			task.spawn(o.Callback, opt)
		end
	end

	local function rebuild()
		for _, b in buttons do
			b:Destroy()
		end
		table.clear(buttons)
		list.Size = UDim2.new(1, -16, 0, listHeight())
		for i, opt in options do
			local b = create("TextButton", {
				Name = tostring(opt),
				Size = UDim2.new(1, -4, 0, OPT),
				LayoutOrder = i,
				BackgroundColor3 = Theme.SurfaceHover,
				BackgroundTransparency = 1,
				Text = tostring(opt),
				TextColor3 = (opt == selected) and Theme.Accent or Theme.Text,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = list,
			}, { corner(6), padding(10, 0, 0, 0) })
			b.MouseEnter:Connect(function()
				A(b, "BackgroundTransparency", 0, P.Snappy)
			end)
			b.MouseLeave:Connect(function()
				A(b, "BackgroundTransparency", 1, P.Snappy)
			end)
			b.Activated:Connect(function()
				choose(opt, true)
				setOpen(false)
			end)
			table.insert(buttons, b)
		end
	end
	rebuild()

	cardHover(card, hit, scale)
	hit.Activated:Connect(function()
		setOpen(not open)
	end)

	return {
		Frame = card,
		Get = function()
			return selected
		end,
		Set = function(_, v)
			choose(v, true)
		end,
		SetOptions = function(_, newOptions)
			options = newOptions
			rebuild()
			if open then
				setOpen(true)
			end
		end,
	}
end

function Container:AddProgress(o)
	o = o or {}
	local card = self:_card(50)
	create("TextLabel", {
		Position = UDim2.fromOffset(14, 8),
		Size = UDim2.new(1, -100, 0, 18),
		Text = o.Text or "Progress",
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	local pct = create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 8),
		Size = UDim2.fromOffset(80, 18),
		Font = Theme.FontBold,
		TextColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = card,
	})
	local track = create("Frame", {
		Position = UDim2.new(0, 14, 0, 32),
		Size = UDim2.new(1, -28, 0, 8),
		BackgroundColor3 = Theme.Stroke,
		Parent = card,
	}, { pill() })
	local fill = create("Frame", {
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
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
		Set = function(_, a)
			set(a, false)
		end,
	}
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
	if self.Opened then
		return
	end
	self.Opened = true
	self.Root.Visible = true
	A(self.Main, "GroupTransparency", 0, P.Smooth)
	A(self.Main, "Position", UDim2.fromOffset(0, 0), P.Smooth)
	A(self.OpenScale, "Scale", 1, P.Bouncy)
end

function Window:Close()
	if not self.Opened then
		return
	end
	self.Opened = false
	A(self.Main, "GroupTransparency", 1, P.Snappy)
	A(self.Main, "Position", UDim2.fromOffset(0, 24), P.Snappy)
	A(self.OpenScale, "Scale", 0.88, P.Snappy)
	task.delay(0.3, function()
		if not self.Opened and self.Root.Parent then
			self.Root.Visible = false
		end
	end)
end

function Window:Toggle()
	if self.Opened then
		self:Close()
	else
		self:Open()
	end
end

function Window:Minimize(state)
	if state == nil then
		state = not self.Minimized
	end
	self.Minimized = state
	local h = state and 46 or self.Size.Y
	A(self.Root, "Size", UDim2.fromOffset(self.Size.X, h), P.Smooth)
end

function Window:SetTitle(title, subtitle)
	local sub = subtitle and ("  <font size=\"12\" color=\"" .. rgbString(Theme.SubText) .. "\">" .. subtitle .. "</font>") or ""
	self.TitleLabel.Text = title .. sub
end

function Window:SelectTab(tab)
	if self.Current == tab then
		return
	end
	local old = self.Current
	self.Current = tab

	A(self.Indicator, "Position", UDim2.fromOffset(2, 10 + (tab.Index - 1) * 42 + 8), P.Bouncy)

	for _, t in self.Tabs do
		local active = t == tab
		A(t.Button, "BackgroundTransparency", active and 0 or 1, P.Snappy)
		A(t.Button, "TextColor3", active and Theme.Text or Theme.SubText, P.Snappy)
	end

	if old then
		A(old.Page, "GroupTransparency", 1, P.Snappy)
		A(old.Page, "Position", UDim2.fromOffset(-24, 0), P.Snappy)
		task.delay(0.25, function()
			if self.Current ~= old then
				old.Page.Visible = false
			end
		end)
	end

	local page = tab.Page
	page.Visible = true
	Nova.Snap(page, "Position", UDim2.fromOffset(24, 0))
	A(page, "Position", UDim2.fromOffset(0, 0), P.Smooth)
	A(page, "GroupTransparency", 0, P.Smooth)

	-- staggered pop-in of every card on the page
	for i, scale in tab.Cards do
		Nova.Snap(scale, "Scale", 0.92)
		task.delay(math.min(i, 10) * 0.035, function()
			A(scale, "Scale", 1, P.Bouncy)
		end)
	end
end

function Window:AddTab(name, icon)
	local idx = #self.Tabs + 1
	local btn = create("TextButton", {
		Name = name,
		Size = UDim2.new(1, 0, 0, 36),
		LayoutOrder = idx,
		BackgroundColor3 = Theme.SurfaceHover,
		BackgroundTransparency = 1,
		Text = (icon and (icon .. "  ") or "") .. name,
		TextColor3 = Theme.SubText,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = self.TabList,
	}, { corner(8), padding(14, 0, 8, 0) })

	local page = create("CanvasGroup", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		GroupTransparency = 1,
		Visible = false,
		Parent = self.Content,
	})
	local scroll = create("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Theme.Accent,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = page,
	}, {
		create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
		padding(12, 12, 16, 12),
	})

	local tab = newContainer(self, scroll)
	tab.Button, tab.Page, tab.Index, tab.Name = btn, page, idx, name
	table.insert(self.Tabs, tab)

	btn.MouseEnter:Connect(function()
		if self.Current ~= tab then
			A(btn, "BackgroundTransparency", 0.6, P.Snappy)
			A(btn, "TextColor3", Theme.Text, P.Snappy)
		end
	end)
	btn.MouseLeave:Connect(function()
		if self.Current ~= tab then
			A(btn, "BackgroundTransparency", 1, P.Snappy)
			A(btn, "TextColor3", Theme.SubText, P.Snappy)
		end
	end)
	btn.Activated:Connect(function()
		self:SelectTab(tab)
	end)

	if not self.Current then
		self:SelectTab(tab)
	end
	return tab
end

function Window:Destroy()
	for _, c in self._conns do
		c:Disconnect()
	end
	table.clear(self._conns)
	if self.OwnsGui then
		self.Gui:Destroy()
	else
		self.Root:Destroy()
	end
end

function Nova.Window(o)
	o = o or {}
	local self = setmetatable({ _conns = {}, Tabs = {}, Opened = false, Minimized = false }, Window)
	local size = o.Size or Vector2.new(580, 400)
	self.Size = size
	self.OwnsGui = o.Gui == nil
	self.Gui = o.Gui or Nova.ScreenGui(o.Name or "NovaWindow")

	-- root holds position / size / fit-to-screen scale
	local root = create("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(size.X, size.Y),
		Visible = false,
		Parent = self.Gui,
	})
	local fit = create("UIScale", { Parent = root })
	self.Root = root

	local function refit()
		local cam = workspace.CurrentCamera
		if cam then
			local v = cam.ViewportSize
			fit.Scale = math.min(1, (v.X - 24) / size.X, (v.Y - 24) / size.Y)
		end
	end
	refit()
	if workspace.CurrentCamera then
		self:_connect(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), refit)
	end

	-- main is a CanvasGroup so the whole window can fade and clips to its corners
	local main = create("CanvasGroup", {
		Name = "Main",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(0, 24),
		BackgroundColor3 = Theme.Background,
		GroupTransparency = 1,
		Parent = root,
	}, { corner(14) })
	self.Main = main
	self.OpenScale = create("UIScale", { Scale = 0.88, Parent = main })

	-- animated rotating gradient border
	local border = stroke(Theme.Accent, 1.5, 0.3)
	border.Parent = main
	local borderGrad = create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Theme.Accent),
			ColorSequenceKeypoint.new(0.5, Theme.AccentAlt),
			ColorSequenceKeypoint.new(1, Theme.Accent),
		}),
		Parent = border,
	})
	self:_connect(RunService.RenderStepped, function()
		if self.Opened then
			borderGrad.Rotation = (os.clock() * 45) % 360
		end
	end)

	-- top bar
	local top = create("Frame", {
		Name = "TopBar",
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundColor3 = Theme.Surface,
		Parent = main,
	})
	create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = Theme.Stroke,
		Parent = top,
	})
	self.TitleLabel = create("TextLabel", {
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.new(1, -110, 1, 0),
		Font = Theme.FontBold,
		TextSize = 16,
		RichText = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = top,
	})
	self:SetTitle(o.Title or "Nova UI", o.Subtitle)

	local function ctrl(text, xOff, hoverColor, cb)
		local b = create("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, xOff, 0.5, 0),
			Size = UDim2.fromOffset(28, 28),
			BackgroundColor3 = Theme.SurfaceHover,
			BackgroundTransparency = 1,
			Text = text,
			Font = Theme.FontBold,
			TextSize = 16,
			TextColor3 = Theme.SubText,
			Parent = top,
		}, { corner(8) })
		local s = create("UIScale", { Parent = b })
		b.MouseEnter:Connect(function()
			A(b, "BackgroundTransparency", 0, P.Snappy)
			A(b, "TextColor3", hoverColor, P.Snappy)
			A(s, "Scale", 1.1, P.Bouncy)
		end)
		b.MouseLeave:Connect(function()
			A(b, "BackgroundTransparency", 1, P.Snappy)
			A(b, "TextColor3", Theme.SubText, P.Snappy)
			A(s, "Scale", 1, P.Snappy)
		end)
		b.MouseButton1Down:Connect(function()
			A(s, "Scale", 0.88, P.Snappy)
		end)
		b.Activated:Connect(cb)
	end
	ctrl("×", -12, Theme.Danger, function()
		self:Close()
	end)
	ctrl("–", -46, Theme.Warning, function()
		self:Minimize()
	end)

	-- sidebar (tab list) + indicator
	local sidebar = create("Frame", {
		Name = "Sidebar",
		Position = UDim2.fromOffset(0, 46),
		Size = UDim2.new(0, 150, 1, -46),
		Parent = main,
	})
	create("Frame", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 1, 1, 0),
		BackgroundColor3 = Theme.Stroke,
		Parent = sidebar,
	})
	self.TabList = create("Frame", { Size = UDim2.fromScale(1, 1), Parent = sidebar }, {
		create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		padding(8, 10, 8, 8),
	})
	self.Indicator = create("Frame", {
		Position = UDim2.fromOffset(2, 18),
		Size = UDim2.fromOffset(3, 20),
		BackgroundColor3 = Theme.Accent,
		ZIndex = 3,
		Parent = sidebar,
	}, { pill() })
	self.Sidebar = sidebar

	self.Content = create("Frame", {
		Name = "Content",
		Position = UDim2.fromOffset(150, 46),
		Size = UDim2.new(1, -150, 1, -46),
		Parent = main,
	})

	-- dragging
	local dragging, dragStart, startPos = false, nil, nil
	top.InputBegan:Connect(function(input)
		if isPress(input) then
			dragging, dragStart, startPos = true, input.Position, root.Position
		end
	end)
	self:_connect(UserInputService.InputChanged, function(input)
		if
			dragging
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			local d = (input.Position - dragStart) / fit.Scale
			Nova.Animate(
				root,
				"Position",
				UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y),
				40,
				1
			)
		end
	end)
	self:_connect(UserInputService.InputEnded, function(input)
		if isPress(input) then
			dragging = false
		end
	end)

	-- toggle keybind
	if o.ToggleKey then
		self:_connect(UserInputService.InputBegan, function(input, processed)
			if not processed and input.KeyCode == o.ToggleKey then
				self:Toggle()
			end
		end)
	end

	if not o.StartHidden then
		task.defer(function()
			self:Open()
		end)
	end
	return self
end

--------------------------------------------------------------------------------
-- Notifications (toasts)
--------------------------------------------------------------------------------

local holder
local toastId = 0

local function getHolder()
	if holder and holder.Parent then
		return holder
	end
	local gui = Nova.ScreenGui("NovaNotifications", 1000)
	holder = create("Frame", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -14, 1, -14),
		Size = UDim2.new(0, 320, 1, -28),
		Parent = gui,
	}, {
		create("UIListLayout", {
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
		}),
	})
	return holder
end

-- Nova.Notify{ Title, Text, Type = "info"|"success"|"warning"|"error", Duration = 4 }
function Nova.Notify(o)
	o = o or {}
	local kinds = { info = Theme.Accent, success = Theme.Success, warning = Theme.Warning, error = Theme.Danger }
	local color = kinds[o.Type or "info"] or Theme.Accent
	local duration = o.Duration or 4
	local H = 72
	toastId += 1

	local wrap = create("Frame", { Size = UDim2.new(1, 0, 0, 0), LayoutOrder = toastId, Parent = getHolder() })
	local card = create("CanvasGroup", {
		Size = UDim2.new(1, 0, 0, H),
		Position = UDim2.fromOffset(340, 0),
		BackgroundColor3 = Theme.Surface,
		GroupTransparency = 1,
		Parent = wrap,
	}, { corner(10), stroke(Theme.Stroke, 1, 0.2) })

	create("Frame", { Size = UDim2.new(0, 4, 1, 0), BackgroundColor3 = color, Parent = card })
	create("TextLabel", {
		Position = UDim2.fromOffset(18, 9),
		Size = UDim2.new(1, -30, 0, 18),
		Text = o.Title or "Notification",
		Font = Theme.FontBold,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	create("TextLabel", {
		Position = UDim2.fromOffset(18, 28),
		Size = UDim2.new(1, -30, 0, 34),
		Text = o.Text or "",
		TextSize = 13,
		TextColor3 = Theme.SubText,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = card,
	})
	local bar = create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = color,
		Parent = card,
	})
	local hit = create("TextButton", { Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = card })

	local closed = false
	local function dismiss()
		if closed then
			return
		end
		closed = true
		A(card, "Position", UDim2.fromOffset(340, 0), P.Snappy)
		A(card, "GroupTransparency", 1, P.Snappy)
		task.delay(0.12, function()
			if wrap.Parent then
				A(wrap, "Size", UDim2.new(1, 0, 0, 0), P.Smooth)
			end
		end)
		task.delay(0.7, function()
			wrap:Destroy()
		end)
	end

	A(wrap, "Size", UDim2.new(1, 0, 0, H), P.Bouncy)
	A(card, "Position", UDim2.fromOffset(0, 0), P.Bouncy)
	A(card, "GroupTransparency", 0, P.Smooth)

	TweenService:Create(bar, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 0, 2) }):Play()
	task.delay(duration, dismiss)
	hit.Activated:Connect(dismiss)

	return { Dismiss = dismiss }
end

--------------------------------------------------------------------------------
-- Dialog (modal)
--------------------------------------------------------------------------------

-- Nova.Dialog{ Title, Text, Buttons = { {Text, Primary, Callback} }, Dismissible = true }
function Nova.Dialog(o)
	o = o or {}
	local gui = Nova.ScreenGui("NovaDialog", 900)

	local dim = create("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	local card = create("CanvasGroup", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(340, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Surface,
		GroupTransparency = 1,
		Parent = gui,
	}, {
		corner(14),
		stroke(Theme.Stroke, 1, 0.2),
		create("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
		padding(18, 18, 18, 18),
	})
	local sc = create("UIScale", { Scale = 0.8, Parent = card })

	create("TextLabel", {
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 24),
		Text = o.Title or "Dialog",
		Font = Theme.FontBold,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = card,
	})
	create("TextLabel", {
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = o.Text or "",
		TextColor3 = Theme.SubText,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = card,
	})
	local row = create("Frame", { LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 38), Parent = card }, {
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 8),
		}),
	})

	local closing = false
	local function close()
		if closing then
			return
		end
		closing = true
		A(dim, "BackgroundTransparency", 1, P.Smooth)
		A(card, "GroupTransparency", 1, P.Snappy)
		A(sc, "Scale", 0.9, P.Snappy)
		task.delay(0.4, function()
			gui:Destroy()
		end)
	end

	for i, b in o.Buttons or { { Text = "OK", Primary = true } } do
		local base = b.Primary and Theme.Accent or Theme.SurfaceHover
		local hover = b.Primary and Theme.AccentAlt or Theme.Stroke
		local btn = create("TextButton", {
			LayoutOrder = i,
			Size = UDim2.fromOffset(96, 34),
			BackgroundColor3 = base,
			Text = b.Text or "OK",
			Font = Theme.FontBold,
			Parent = row,
		}, { corner(8) })
		local s = create("UIScale", { Parent = btn })
		hoverable(btn, btn, s, base, hover, 1.05)
		btn.Activated:Connect(function()
			close()
			if b.Callback then
				task.spawn(b.Callback)
			end
		end)
	end

	if o.Dismissible ~= false then
		dim.Activated:Connect(close)
	end

	A(dim, "BackgroundTransparency", 0.45, P.Smooth)
	A(card, "GroupTransparency", 0, P.Smooth)
	A(sc, "Scale", 1, P.Bouncy)

	return { Close = close }
end

return Nova

-- The kitchen display: one ticket per order being prepared, oldest first, with a timer that
-- turns amber then red. Staff tap Ready; ready orders wait in the strip at the bottom until
-- staff tap Collected (or they clear by themselves). Everyone sees the tickets; only staff
-- get the buttons.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("POS")
local Config = require(Shared.Config)
local Roles = require(Shared.Roles)

local Client = script.Parent.Parent
local Api = require(Client.Api)
local State = require(Client.State)
local UI = require(Client.UI.UI)
local Theme = require(Client.UI.Theme)
local Toasts = require(Client.UI.Toasts)

local C, F = Theme.Colors, Theme.Fonts

local Kitchen = {}

local PIXELS_PER_STUD = 100
local MAX_TICKETS = 5

local player = Players.LocalPlayer
local displays = {}

local function elapsed(placedAt: number): number
	return math.max(0, os.time() - placedAt)
end

local function timerText(seconds: number): string
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

local function ageColour(seconds: number): Color3
	local late = Config.Orders.LateAfter
	if seconds >= late[2] then
		return C.Danger
	elseif seconds >= late[1] then
		return C.Warning
	end
	return C.Success
end

local function act(action: string, number: number)
	local ok, err = Api.call(action, number)
	if not ok then
		Toasts.show(err, "error")
	end
end

local function mount(instance: Instance)
	local screen = instance:FindFirstChild("Screen", true)
	if not screen or not screen:IsA("BasePart") or displays[instance] then
		return
	end
	local canvas = Vector2.new(screen.Size.X, screen.Size.Y) * PIXELS_PER_STUD
	local gui = UI.new("SurfaceGui", {
		Name = "RoPOSKitchen",
		Adornee = screen,
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
		CanvasSize = canvas,
		LightInfluence = 0,
		Brightness = 1.3,
		MaxDistance = 60,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local root = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Bg, Parent = gui })
	local timers: { { label: TextLabel, bar: Frame, placedAt: number } } = {}
	local unit = canvas.Y / 100

	local function render()
		UI.clear(root)
		table.clear(timers)
		local staff = State.role >= Roles.Cashier

		local preparing, ready = {}, {}
		for _, ticket in State.orders do
			table.insert(if ticket.status == "ready" then ready else preparing, ticket)
		end

		-- Header
		local header = UI.new("Frame", {
			BackgroundColor3 = C.Text,
			Size = UDim2.new(1, 0, 0, 11 * unit),
			Parent = root,
		})
		UI.text({
			Text = "Kitchen",
			FontFace = F.Heavy,
			TextSize = 6.5 * unit,
			TextColor3 = C.Panel,
			Position = UDim2.fromOffset(3 * unit, 0),
			Size = UDim2.fromScale(0.4, 1),
			Parent = header,
		})
		UI.text({
			Text = string.format("%d preparing · %d ready", #preparing, #ready),
			FontFace = F.Medium,
			TextSize = 4.5 * unit,
			TextColor3 = C.Faint,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -3 * unit, 0, 0),
			Size = UDim2.fromScale(0.6, 1),
			Parent = header,
		})

		-- Tickets
		local strip = 17 * unit
		local area = UI.new("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(2 * unit, 13 * unit),
			Size = UDim2.new(1, -4 * unit, 1, -(15 * unit + strip)),
			Parent = root,
			Children = {
				UI.new("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					Padding = UDim.new(0, 1.5 * unit),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			},
		})
		if #preparing == 0 then
			UI.text({
				Text = "No orders waiting",
				FontFace = F.Bold,
				TextSize = 6 * unit,
				TextColor3 = C.Faint,
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.fromScale(1, 1),
				Parent = area,
			})
		end
		for index, ticket in preparing do
			if index > MAX_TICKETS then
				break
			end
			local age = elapsed(ticket.placedAt)
			local card = UI.new("Frame", {
				BackgroundColor3 = C.Panel,
				Size = UDim2.new(1 / MAX_TICKETS, -1.3 * unit, 1, 0),
				LayoutOrder = index,
				Parent = area,
				Children = { UI.corner(math.floor(1.5 * unit)), UI.stroke(C.Border, 1) },
			})
			local bar = UI.new("Frame", {
				BackgroundColor3 = ageColour(age),
				Size = UDim2.new(1, 0, 0, 13 * unit),
				Parent = card,
				Children = { UI.corner(math.floor(1.5 * unit)) },
			})
			UI.text({
				Text = "#" .. ticket.number,
				FontFace = F.Heavy,
				TextSize = 7 * unit,
				TextColor3 = C.Panel,
				Position = UDim2.fromOffset(2 * unit, 0),
				Size = UDim2.new(0.6, 0, 0, 8 * unit),
				Parent = bar,
			})
			local timer = UI.text({
				Text = timerText(age),
				FontFace = F.Mono,
				TextSize = 4.5 * unit,
				TextColor3 = C.Panel,
				TextXAlignment = Enum.TextXAlignment.Right,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -2 * unit, 0, 1.5 * unit),
				Size = UDim2.new(0.4, 0, 0, 6 * unit),
				Parent = bar,
			})
			UI.text({
				Text = ticket.source .. (if ticket.dining then " · " .. ticket.dining else ""),
				FontFace = F.Medium,
				TextSize = 3.4 * unit,
				TextColor3 = C.Panel,
				Position = UDim2.fromOffset(2 * unit, 8 * unit),
				Size = UDim2.new(1, -4 * unit, 0, 4.5 * unit),
				Parent = bar,
			})
			table.insert(timers, { label = timer, bar = bar, placedAt = ticket.placedAt })

			local lines = UI.new("Frame", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(2 * unit, 15 * unit),
				Size = UDim2.new(1, -4 * unit, 1, -(if staff then 31 else 17) * unit),
				Parent = card,
				Children = { UI.list(0.6 * unit) },
			})
			for i, line in ticket.lines do
				UI.text({
					Text = string.format("%d × %s", line.qty, line.name),
					FontFace = F.Bold,
					TextSize = 4 * unit,
					TextWrapped = true,
					AutomaticSize = Enum.AutomaticSize.Y,
					Size = UDim2.new(1, 0, 0, 5 * unit),
					LayoutOrder = i,
					Parent = lines,
				})
			end
			UI.text({
				Text = ticket.customer,
				TextSize = 3.2 * unit,
				TextColor3 = C.Muted,
				LayoutOrder = 100,
				Size = UDim2.new(1, 0, 0, 4.5 * unit),
				Parent = lines,
			})
			if staff then
				UI.button({
					Text = "Ready",
					Style = "success",
					TextSize = 5 * unit,
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.new(0.5, 0, 1, -1.5 * unit),
					Size = UDim2.new(1, -3 * unit, 0, 12 * unit),
					Radius = UDim.new(0, math.floor(1.2 * unit)),
					Parent = card,
					OnClick = function()
						act("orders.ready", ticket.number)
					end,
				})
			end
		end
		if #preparing > MAX_TICKETS then
			UI.pill("+" .. (#preparing - MAX_TICKETS) .. " more", C.Panel, C.Text, {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -3 * unit, 0, 13.5 * unit),
				Size = UDim2.fromOffset(0, 6 * unit),
				Parent = root,
			})
		end

		-- Ready strip
		local readyBar = UI.new("Frame", {
			BackgroundColor3 = C.SuccessSoft,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, strip),
			Parent = root,
			Children = {
				UI.padding(math.floor(2 * unit)),
				UI.list(
					1.5 * unit,
					Enum.FillDirection.Horizontal,
					{ VerticalAlignment = Enum.VerticalAlignment.Center }
				),
			},
		})
		UI.text({
			Text = "Ready for collection",
			FontFace = F.Heavy,
			TextSize = 4.2 * unit,
			TextColor3 = C.Success,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 10 * unit),
			LayoutOrder = 0,
			Parent = readyBar,
		})
		for i, ticket in ready do
			if i > 6 then
				break
			end
			local chip = UI.new("Frame", {
				BackgroundColor3 = C.Panel,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 12 * unit),
				LayoutOrder = i,
				Parent = readyBar,
				Children = {
					UI.corner(math.floor(1.2 * unit)),
					UI.padding(0, math.floor(1.5 * unit)),
					UI.list(unit, Enum.FillDirection.Horizontal, { VerticalAlignment = Enum.VerticalAlignment.Center }),
					UI.text({
						Text = "#" .. ticket.number,
						FontFace = F.Heavy,
						TextSize = 5 * unit,
						TextColor3 = C.Success,
						AutomaticSize = Enum.AutomaticSize.X,
						Size = UDim2.fromOffset(0, 10 * unit),
					}),
				},
			})
			if staff then
				UI.button({
					Text = "Collected",
					Style = "secondary",
					TextSize = 3.4 * unit,
					Size = UDim2.fromOffset(17 * unit, 8.5 * unit),
					LayoutOrder = 2,
					Parent = chip,
					OnClick = function()
						act("orders.collect", ticket.number)
					end,
				})
				UI.button({
					Text = "Recall",
					Style = "ghost",
					TextSize = 3.4 * unit,
					Size = UDim2.fromOffset(12 * unit, 8.5 * unit),
					LayoutOrder = 3,
					Parent = chip,
					OnClick = function()
						act("orders.recall", ticket.number)
					end,
				})
			end
		end
	end

	displays[instance] = { render = render }
	render()

	-- Tick the timers without redrawing everything.
	task.spawn(function()
		while gui.Parent do
			task.wait(1)
			for _, timer in timers do
				local age = elapsed(timer.placedAt)
				timer.label.Text = timerText(age)
				timer.bar.BackgroundColor3 = ageColour(age)
			end
		end
	end)
end

function Kitchen.mount()
	for _, instance in CollectionService:GetTagged(Config.Tags.Kitchen) do
		task.spawn(mount, instance)
	end
	CollectionService:GetInstanceAddedSignal(Config.Tags.Kitchen):Connect(function(instance)
		task.spawn(mount, instance)
	end)
	State.changed:Connect(function(key)
		if key == "orders" or key == "role" then
			for _, display in displays do
				display.render()
			end
		end
	end)
end

return Kitchen

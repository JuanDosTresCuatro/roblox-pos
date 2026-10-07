-- Physical registers. Tag any Model or BasePart with "POSRegister" (CollectionService) and it
-- becomes a working till with a ProximityPrompt and a customer-facing screen.
--
-- Optional attributes on the tagged instance:
--   RegisterId   (string) stable id, generated if missing
--   RegisterName (string) shown to staff and customers
-- Optional child: a BasePart named "Screen" for the customer "Your order" display (front face).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("POS")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Palette = require(Shared.Palette)
local Signal = require(Shared.Signal)
local Api = require(script.Parent.Api)
local Staff = require(script.Parent.Staff)
local Shifts = require(script.Parent.Shifts)
local Surface = require(script.Parent.Surface)

local Registers = {}
Registers.released = Signal.new() -- (register, reason)

export type PreviewLine = { name: string, qty: number, total: number }

export type Register = {
	id: string,
	name: string,
	instance: Instance,
	anchor: BasePart,
	prompt: ProximityPrompt,
	screen: BasePart,
	operator: Player?,
	shift: Shifts.Shift?,
	order: any?, -- the pending Checkout order, if any
	preview: { items: number, total: number, discount: number, lines: { PreviewLine } }?,
	flashUntil: number,
	flashNumber: number?,
}

local registers: { [string]: Register } = {}
local byInstance: { [Instance]: Register } = {}
local byOperator: { [Player]: Register } = {}
local count = 0

local F = Surface.Fonts
local MAX_LINES = 5

local function money(n: number): string
	return Format.money(n, Config.Currency.Symbol)
end

-- The customer-facing "Your order" screen. Redrawn from scratch on every change.
local function draw(register: Register, state)
	local _, root, size = Surface.create(register.screen, "RoPOSDisplay")
	local unit = size.Y / 100

	-- Header: store name and a coloured strip that shows the state at a glance.
	Surface.box(root, { Size = UDim2.new(1, 0, 0, 3 * unit), BackgroundColor3 = state.colour })
	Surface.text(root, {
		Text = Config.Store.Name,
		FontFace = F.Heavy,
		TextSize = 9 * unit,
		Position = UDim2.fromOffset(6 * unit, 7 * unit),
		Size = UDim2.new(0.6, 0, 0, 10 * unit),
	})
	Surface.text(root, {
		Text = register.name,
		FontFace = F.Medium,
		TextSize = 7 * unit,
		TextColor3 = Palette.Muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -6 * unit, 0, 8 * unit),
		Size = UDim2.new(0.4, 0, 0, 9 * unit),
	})

	local status = Surface.text(root, {
		Name = "Status",
		Text = state.status,
		FontFace = F.Heavy,
		TextSize = (if state.lines then 11 else 19) * unit,
		Position = UDim2.fromOffset(6 * unit, 22 * unit),
		Size = UDim2.new(1, -12 * unit, 0, (if state.lines then 12 else 22) * unit),
	})

	if state.lines then
		local list = Surface.new("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(6 * unit, 36 * unit),
			Size = UDim2.new(1, -12 * unit, 0, 40 * unit),
			Parent = root,
		})
		Surface.new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
		local shown = math.min(#state.lines, MAX_LINES)
		for i = 1, shown do
			local line = state.lines[i]
			local text = if i == MAX_LINES and #state.lines > MAX_LINES
				then string.format("+ %d more", #state.lines - MAX_LINES + 1)
				else string.format("%d × %s", line.qty, line.name)
			local row = Surface.new("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 8 * unit),
				LayoutOrder = i,
				Parent = list,
			})
			Surface.text(
				row,
				{ Text = text, FontFace = F.Medium, TextSize = 6.4 * unit, Size = UDim2.fromScale(0.75, 1) }
			)
			if not (i == MAX_LINES and #state.lines > MAX_LINES) then
				Surface.text(row, {
					Text = money(line.total),
					FontFace = F.Mono,
					TextSize = 6 * unit,
					TextXAlignment = Enum.TextXAlignment.Right,
					Position = UDim2.fromScale(0.75, 0),
					Size = UDim2.fromScale(0.25, 1),
				})
			end
		end
	else
		Surface.text(root, {
			Text = state.detail,
			FontFace = F.Medium,
			TextSize = 8 * unit,
			TextColor3 = Palette.Muted,
			Position = UDim2.fromOffset(6 * unit, 46 * unit),
			Size = UDim2.new(1, -12 * unit, 0, 10 * unit),
		})
	end

	-- Footer: the total on a yellow bar, or the order number after payment.
	if state.total or state.number then
		local bar = Surface.box(root, {
			BackgroundColor3 = state.barColour or Palette.Accent,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 20 * unit),
		})
		local ink = state.barInk or Palette.OnAccent
		Surface.text(bar, {
			Text = state.barLabel or "Total",
			FontFace = F.Bold,
			TextSize = 8 * unit,
			TextColor3 = ink,
			Position = UDim2.fromOffset(6 * unit, 0),
			Size = UDim2.fromScale(0.6, 1),
		})
		Surface.text(bar, {
			Text = if state.number then "Order " .. state.number else state.total,
			FontFace = F.Heavy,
			TextSize = 12 * unit,
			TextColor3 = ink,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -6 * unit, 0, 0),
			Size = UDim2.fromScale(0.5, 1),
		})
	end
	return status
end

function Registers.updateDisplay(register: Register)
	local operator = register.operator
	register.prompt.ObjectText = if operator then register.name .. " · " .. operator.DisplayName else register.name

	local state
	if os.clock() < register.flashUntil then
		state = {
			status = "Thank you!",
			detail = if register.flashNumber then "Watch the board for your number" else "Payment approved",
			colour = Palette.Success,
			number = register.flashNumber,
			barColour = Palette.Success,
			barInk = Palette.OnSuccess,
			barLabel = "Your order number",
		}
	elseif register.order then
		local lines = {}
		for _, line in register.order.totals.lines do
			table.insert(
				lines,
				{ name = line.name or line.productId, qty = line.qty, total = line.unitPrice * line.qty }
			)
		end
		state = {
			status = "Please approve",
			lines = lines,
			colour = Palette.Warning,
			total = money(register.order.totals.total),
			barLabel = "Approve on your screen",
		}
	elseif operator and register.preview and register.preview.items > 0 then
		state = {
			status = "Your order",
			lines = register.preview.lines,
			colour = Palette.Accent,
			total = money(register.preview.total),
			barLabel = if register.preview.discount > 0
				then "Total (" .. money(register.preview.discount) .. " off)"
				else "Total",
		}
	elseif operator and register.shift then
		state =
			{ status = "Welcome!", detail = operator.DisplayName .. " can take your order", colour = Palette.Accent }
	elseif register.shift then
		state = { status = "Back soon", detail = "Waiting for a cashier", colour = Palette.Faint }
	else
		state = { status = "Closed", detail = register.name, colour = Palette.Faint }
	end
	draw(register, state)
end

function Registers.flashPaid(register: Register, orderNumber: number?)
	register.flashUntil = os.clock() + 5
	register.flashNumber = orderNumber
	register.preview = nil
	Registers.updateDisplay(register)
	local flashedAt = register.flashUntil
	task.delay(5.1, function()
		if register.flashUntil == flashedAt then
			Registers.updateDisplay(register)
		end
	end)
end

function Registers.summary(register: Register)
	return {
		id = register.id,
		name = register.name,
		shift = if register.shift then Shifts.report(register.shift) else nil,
	}
end

function Registers.distance(register: Register, player: Player): number
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return math.huge
	end
	return (root.Position - register.anchor.Position).Magnitude
end

function Registers.of(player: Player): Register?
	return byOperator[player]
end

function Registers.get(id: string): Register?
	return registers[id]
end

function Registers.release(register: Register, reason: string?)
	local operator = register.operator
	if not operator then
		return
	end
	Registers.released:Fire(register, reason or "The register was closed")
	register.operator = nil
	register.preview = nil
	byOperator[operator] = nil
	Api.push(operator, "CloseRegister", { id = register.id, reason = reason })
	Registers.updateDisplay(register)
end

function Registers.claim(register: Register, player: Player)
	if not Staff.isStaff(player) then
		Api.toast(player, "Only staff can use the register", "warning")
		return
	end
	if register.operator and register.operator ~= player then
		Api.toast(player, register.name .. " is being used by " .. register.operator.DisplayName, "warning")
		return
	end
	local current = byOperator[player]
	if current and current ~= register then
		Registers.release(current, "You moved to " .. register.name)
	end
	register.operator = player
	byOperator[player] = register
	Api.push(player, "OpenRegister", Registers.summary(register))
	Registers.updateDisplay(register)
end

-- Pushes fresh register details (shift totals) to the operator.
function Registers.refreshOperator(register: Register)
	if register.operator then
		Api.push(register.operator, "Register", Registers.summary(register))
	end
end

local function findAnchor(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	elseif instance:IsA("Model") and instance.PrimaryPart then
		return instance.PrimaryPart
	end
	return instance:FindFirstChildWhichIsA("BasePart", true)
end

-- The customer screen: a Part named "Screen", or a small one made above the till.
local function findScreen(instance: Instance, anchor: BasePart): BasePart
	local screen = instance:FindFirstChild("Screen", true)
	if screen and screen:IsA("BasePart") then
		return screen
	end
	local made = Instance.new("Part")
	made.Name = "Screen"
	made.Anchored = true
	made.CanCollide = false
	made.Size = Vector3.new(3.2, 2, 0.1)
	made.Color = Palette.Bezel
	made.CFrame = anchor.CFrame * CFrame.new(0, anchor.Size.Y / 2 + 1.6, 0)
	made.Parent = instance
	return made
end

local function add(instance: Instance)
	if byInstance[instance] then
		return
	end
	local anchor = findAnchor(instance)
	if not anchor then
		warn("[RoPOS] " .. instance:GetFullName() .. " is tagged " .. Config.RegisterTag .. " but has no parts")
		return
	end

	count += 1
	local id = instance:GetAttribute("RegisterId")
	if typeof(id) ~= "string" or id == "" or registers[id] then
		id = "R" .. count
		instance:SetAttribute("RegisterId", id)
	end
	local name = instance:GetAttribute("RegisterName")
	if typeof(name) ~= "string" or name == "" then
		name = "Register " .. count
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RoPOSPrompt"
	prompt.ActionText = "Use register"
	prompt.ObjectText = name
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor

	local register: Register = {
		id = id,
		name = name,
		instance = instance,
		anchor = anchor,
		prompt = prompt,
		screen = findScreen(instance, anchor),
		operator = nil,
		shift = nil,
		order = nil,
		preview = nil,
		flashUntil = 0,
		flashNumber = nil,
	}
	registers[id] = register
	byInstance[instance] = register

	prompt.Triggered:Connect(function(player)
		Registers.claim(register, player)
	end)
	Registers.updateDisplay(register)
end

local function remove(instance: Instance)
	local register = byInstance[instance]
	if not register then
		return
	end
	Registers.release(register, "The register was removed")
	register.prompt:Destroy()
	byInstance[instance] = nil
	registers[register.id] = nil
end

function Registers.all(): { Register }
	local out = {}
	for _, register in registers do
		table.insert(out, register)
	end
	return out
end

function Registers.init()
	for _, instance in CollectionService:GetTagged(Config.RegisterTag) do
		add(instance)
	end
	CollectionService:GetInstanceAddedSignal(Config.RegisterTag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(Config.RegisterTag):Connect(remove)

	Players.PlayerRemoving:Connect(function(player)
		local register = byOperator[player]
		if register then
			Registers.release(register, "The cashier left")
		end
	end)

	-- Sign the cashier out when they walk away.
	task.spawn(function()
		while true do
			task.wait(1)
			for _, register in registers do
				local operator = register.operator
				if operator and Registers.distance(register, operator) > Config.Checkout.OperatorRange then
					Registers.release(register, "You walked away from " .. register.name)
				end
			end
		end
	end)
end

return Registers

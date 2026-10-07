-- Screens everyone sees the same way, drawn by the server:
--   POSOrderBoard  "Preparing" and "Ready" order numbers
--   POSMenuBoard   menu with live prices and sold-out marks. Attribute Category = one category.
-- Tag a Part (or a Model with a Part named "Screen"); the front face is drawn on.

local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("POS")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Palette = require(Shared.Palette)
local Catalogue = require(script.Parent.Catalogue)
local Orders = require(script.Parent.Orders)
local Surface = require(script.Parent.Surface)

local Boards = {}

local F = Surface.Fonts
local GUI_NAME = "RoPOSBoard"

local function screenOf(instance: Instance): BasePart?
	local screen = instance:FindFirstChild("Screen", true)
	if screen and screen:IsA("BasePart") then
		return screen
	end
	return if instance:IsA("BasePart") then instance else nil
end

------------------------------------------------------------------------ order board

local function drawOrderBoard(part: BasePart)
	local _, root, size = Surface.create(part, GUI_NAME)
	local unit = size.Y / 100 -- 1% of the board height
	local header = 16 * unit

	local preparing, ready = {}, {}
	for _, ticket in Orders.list() do
		table.insert(if ticket.status == "ready" then ready else preparing, ticket.number)
	end

	local function column(x: number, title: string, fill: Color3, ink: Color3, numbers: { number }, big: boolean)
		local col = Surface.box(root, {
			Position = UDim2.new(x, 2 * unit, 0, 2 * unit),
			Size = UDim2.new(0.5, -3 * unit, 1, -4 * unit),
			BackgroundColor3 = Palette.Raised,
			Radius = math.floor(3 * unit),
		})
		local bar = Surface.box(
			col,
			{ Size = UDim2.new(1, 0, 0, header), BackgroundColor3 = fill, Radius = math.floor(3 * unit) }
		)
		Surface.text(bar, {
			Text = title,
			TextColor3 = ink,
			FontFace = F.Heavy,
			TextSize = 9 * unit,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1),
		})
		local grid = Surface.new("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(3 * unit, header + 3 * unit),
			Size = UDim2.new(1, -6 * unit, 1, -(header + 6 * unit)),
			Parent = col,
		})
		Surface.new("UIGridLayout", {
			CellSize = UDim2.new(1 / 3, -2 * unit, 0, 16 * unit),
			CellPadding = UDim2.fromOffset(2 * unit, 2 * unit),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = grid,
		})
		for index, number in numbers do
			if index > 12 then
				break
			end
			Surface.text(grid, {
				Text = tostring(number),
				LayoutOrder = index,
				FontFace = F.Heavy,
				TextSize = (if big then 14 else 12) * unit,
				TextColor3 = if big then Palette.Success else Palette.Text,
				TextXAlignment = Enum.TextXAlignment.Center,
			})
		end
	end

	column(0, "Preparing", Palette.Accent, Palette.OnAccent, preparing, false)
	column(0.5, "Ready", Palette.Success, Palette.OnSuccess, ready, true)
end

------------------------------------------------------------------------ menu board

local function drawMenuBoard(part: BasePart, category: string?)
	local _, root, size = Surface.create(part, GUI_NAME)
	local unit = size.Y / 100

	local products = {}
	for _, product in Catalogue.list() do
		if product.active and (not category or product.category == category) then
			table.insert(products, product)
		end
	end

	Surface.text(root, {
		Text = category or Config.Store.Name,
		FontFace = F.Heavy,
		TextSize = 13 * unit,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 3 * unit),
		Size = UDim2.new(1, 0, 0, 15 * unit),
	})
	Surface.box(root, {
		BackgroundColor3 = Palette.Accent,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 19 * unit),
		Size = UDim2.fromOffset(22 * unit, 1.4 * unit),
		Radius = math.floor(unit),
	})

	local columns = if #products <= 4 then #products elseif #products <= 8 then 4 else 5
	local rows = math.max(1, math.ceil(#products / math.max(columns, 1)))
	local grid = Surface.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(4 * unit, 25 * unit),
		Size = UDim2.new(1, -8 * unit, 1, -29 * unit),
		Parent = root,
	})
	Surface.new("UIGridLayout", {
		CellSize = UDim2.new(1 / math.max(columns, 1), -3 * unit, 1 / rows, -3 * unit),
		CellPadding = UDim2.fromOffset(3 * unit, 3 * unit),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	for index, product in products do
		local soldOut = product.stock ~= nil and product.stock <= 0
		local tile = Surface.new("Frame", { BackgroundTransparency = 1, LayoutOrder = index, Parent = grid })
		local swatch = Surface.box(tile, {
			BackgroundColor3 = product.colour,
			BackgroundTransparency = if soldOut then 0.6 else 0,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromScale(0.42, 0.42),
		})
		Surface.new("UIAspectRatioConstraint", { AspectRatio = 1, Parent = swatch })
		Surface.new("UICorner", { CornerRadius = UDim.new(1, 0), Parent = swatch })
		Surface.text(swatch, {
			Text = string.upper(string.sub(product.name, 1, 1)),
			FontFace = F.Heavy,
			TextScaled = true,
			TextColor3 = Color3.new(1, 1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1),
		})
		Surface.text(tile, {
			Text = product.name,
			FontFace = F.Bold,
			TextSize = 5.2 * unit,
			TextColor3 = if soldOut then Palette.Faint else Palette.Text,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromScale(0, 0.47),
			Size = UDim2.fromScale(1, 0.24),
		})
		Surface.text(tile, {
			Text = if soldOut then "Sold out" else Format.money(product.price, Config.Currency.Symbol),
			FontFace = F.Heavy,
			TextSize = 6 * unit,
			TextColor3 = if soldOut then Palette.Danger else Palette.AccentText,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromScale(0, 0.72),
			Size = UDim2.fromScale(1, 0.24),
		})
	end
end

------------------------------------------------------------------------ wiring

local orderBoards: { BasePart } = {}
local menuBoards: { { part: BasePart, category: string? } } = {}

local function redrawOrders()
	for _, part in orderBoards do
		drawOrderBoard(part)
	end
end

local function redrawMenus()
	for _, board in menuBoards do
		drawMenuBoard(board.part, board.category)
	end
end

local function watch(tag: string, onAdd: (Instance, BasePart) -> ())
	local function add(instance: Instance)
		local part = screenOf(instance)
		if part then
			onAdd(instance, part)
		else
			warn("[RoPOS] " .. instance:GetFullName() .. " is tagged " .. tag .. " but has no Screen part")
		end
	end
	for _, instance in CollectionService:GetTagged(tag) do
		add(instance)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(add)
end

function Boards.init()
	watch(Config.Tags.OrderBoard, function(_, part)
		table.insert(orderBoards, part)
		drawOrderBoard(part)
	end)
	watch(Config.Tags.MenuBoard, function(instance, part)
		local category = instance:GetAttribute("Category")
		local board =
			{ part = part, category = if typeof(category) == "string" and category ~= "" then category else nil }
		table.insert(menuBoards, board)
		drawMenuBoard(board.part, board.category)
	end)
	Orders.changed:Connect(redrawOrders)
	Catalogue.changed:Connect(redrawMenus)
end

-- For tests: the numbers currently on an order board.
function Boards.orderBoards(): { BasePart }
	return orderBoards
end

return Boards

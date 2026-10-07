-- Builds a demo restaurant when the place has no register: a wall of screens (order status
-- board, kitchen display, a big "Your order" screen, menu boards), a counter with a POS
-- terminal, and a black and a white self-order kiosk. Also creates simple item Tools for
-- products that have no Tool in ServerStorage.POSItems. Turn both off in Config.Demo.
--
-- Layout, seen from the customers' side (+Z), all screens facing the customers:
--
--   [ Order board ][                ][            ][ Tools     ]
--   [ Kitchen     ][   Your order   ][   Gear     ][ Cosmetics ]
--   [ Snacks      ][                ][            ]
--                     [ counter + till ]              (kiosk) (kiosk)

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("POS")
local Config = require(Shared.Config)
local Palette = require(Shared.Palette)

local Demo = {}

local FRONT = Vector3.new(0, 0, 1) -- the direction the customers look from

local function part(parent: Instance, props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

-- A part whose front face looks along `facing`.
local function facingCFrame(position: Vector3, facing: Vector3): CFrame
	return CFrame.lookAt(position, position + facing)
end

local function groundY(x: number, z: number): number
	local result = workspace:Raycast(Vector3.new(x, 500, z), Vector3.new(0, -1000, 0))
	return if result then result.Position.Y else 0
end

local function tag(instance: Instance, name: string, attributes: { [string]: any }?)
	for key, value in (attributes or {}) :: { [string]: any } do
		instance:SetAttribute(key, value)
	end
	CollectionService:AddTag(instance, name)
end

-- A flat panel screen: a dark bezel with a "Screen" part on its front. Returns the model.
local function wallScreen(parent: Instance, name: string, centre: Vector3, width: number, height: number): Model
	local model = Instance.new("Model")
	model.Name = name
	local bezel = part(model, {
		Name = "Bezel",
		Size = Vector3.new(width, height, 0.4),
		CFrame = facingCFrame(centre, FRONT),
		Color = Palette.Bezel,
	})
	part(model, {
		Name = "Screen",
		Size = Vector3.new(width - 0.36, height - 0.36, 0.05),
		CFrame = bezel.CFrame * CFrame.new(0, 0, -0.23),
		Color = Palette.Panel,
		CanCollide = false,
	})
	model.PrimaryPart = bezel
	model.Parent = parent
	return model
end

local function buildRoom(world: Instance, base: CFrame)
	part(world, {
		Name = "Floor",
		Size = Vector3.new(70, 0.2, 44),
		CFrame = base * CFrame.new(0, 0.1, 4),
		Color = Color3.fromRGB(238, 238, 234),
		Material = Enum.Material.Plastic,
	})
	part(world, {
		Name = "BackWall",
		Size = Vector3.new(70, 24, 1),
		CFrame = base * CFrame.new(0, 12, -12.5),
		Color = Color3.fromRGB(232, 233, 236),
	})
	part(world, {
		Name = "Skirting",
		Size = Vector3.new(70, 0.6, 0.2),
		CFrame = base * CFrame.new(0, 0.5, -11.9),
		Color = Palette.Steel,
	})
end

local function buildScreens(world: Instance, base: CFrame, register: Model)
	local z = -11.7
	local board = wallScreen(world, "Order Board", (base * CFrame.new(-23, 18.6, z)).Position, 12, 6.4)
	tag(board, Config.Tags.OrderBoard)

	local kitchen = wallScreen(world, "Kitchen Display", (base * CFrame.new(-23, 11.6, z)).Position, 12, 6.4)
	tag(kitchen, Config.Tags.Kitchen)

	local snacks = wallScreen(world, "Menu Snacks", (base * CFrame.new(-23, 4.6, z)).Position, 12, 6.4)
	tag(snacks, Config.Tags.MenuBoard, { Category = "Snacks" })

	-- The till's customer screen is the big wall display, so it belongs to the register model.
	local yourOrder = wallScreen(register, "Your Order", (base * CFrame.new(-6, 11.6, z)).Position, 15, 13.6)
	yourOrder.Bezel.Name = "YourOrderBezel"
	yourOrder.Screen.Parent = register

	local gear = wallScreen(world, "Menu Gear", (base * CFrame.new(10.5, 11.6, z)).Position, 13, 13.6)
	tag(gear, Config.Tags.MenuBoard, { Category = "Gear" })

	local tools = wallScreen(world, "Menu Tools", (base * CFrame.new(25.5, 15.3, z)).Position, 11, 6.2)
	tag(tools, Config.Tags.MenuBoard, { Category = "Tools" })
	local cosmetics = wallScreen(world, "Menu Cosmetics", (base * CFrame.new(25.5, 8.4, z)).Position, 11, 6.2)
	tag(cosmetics, Config.Tags.MenuBoard, { Category = "Cosmetics" })
end

-- The counter with a POS terminal facing the staff and a card reader facing the customer.
local function buildCounter(base: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "RoPOS Counter"
	local at = base * CFrame.new(-6, 0, -1)

	part(model, {
		Name = "Counter",
		Size = Vector3.new(16, 3.6, 3),
		CFrame = at * CFrame.new(0, 1.8, 0),
		Color = Palette.WhiteBody,
	})
	part(model, {
		Name = "Top",
		Size = Vector3.new(16.4, 0.25, 3.4),
		CFrame = at * CFrame.new(0, 3.72, 0),
		Color = Palette.Steel,
	})
	part(model, {
		Name = "Kick",
		Size = Vector3.new(16, 0.5, 0.2),
		CFrame = at * CFrame.new(0, 0.25, 1.55),
		Color = Palette.Accent,
		Material = Enum.Material.Neon,
	})

	local till = part(model, {
		Name = "Till",
		Size = Vector3.new(1.8, 0.2, 1.4),
		CFrame = at * CFrame.new(0, 3.95, -0.3),
		Color = Palette.Bezel,
	})
	part(model, {
		Name = "Neck",
		Size = Vector3.new(0.25, 1.1, 0.25),
		CFrame = at * CFrame.new(0, 4.6, -0.3),
		Color = Palette.Steel,
	})
	-- Terminal screen, tilted back towards the staff.
	local terminalPos = (at * CFrame.new(0, 5.6, -0.45)).Position
	local terminal = part(model, {
		Name = "Terminal",
		Size = Vector3.new(2.6, 1.7, 0.18),
		CFrame = CFrame.lookAt(terminalPos, terminalPos + Vector3.new(0, 0.35, -1)),
		Color = Palette.Bezel,
	})
	part(model, {
		Name = "TerminalGlass",
		Size = Vector3.new(2.4, 1.5, 0.02),
		CFrame = terminal.CFrame * CFrame.new(0, 0, -0.1),
		Color = Palette.Panel,
		Material = Enum.Material.Neon,
		Transparency = 0.15,
		CanCollide = false,
	})
	part(model, {
		Name = "CardReader",
		Size = Vector3.new(0.6, 0.14, 0.9),
		CFrame = at * CFrame.new(1.6, 3.92, 1.05) * CFrame.Angles(math.rad(-15), 0, 0),
		Color = Palette.Bezel,
	})
	part(model, {
		Name = "ReceiptPrinter",
		Size = Vector3.new(0.9, 0.6, 0.9),
		CFrame = at * CFrame.new(-1.7, 4.15, -0.4),
		Color = Palette.WhiteBody,
	})

	model.PrimaryPart = till
	model:SetAttribute("RegisterId", "R1")
	model:SetAttribute("RegisterName", "Front Counter")
	return model
end

-- A standing self-order kiosk with a portrait touchscreen, card reader and receipt slot.
local function buildKiosk(world: Instance, base: CFrame, x: number, id: string, white: boolean)
	local model = Instance.new("Model")
	model.Name = "Kiosk " .. id
	local at = base * CFrame.new(x, 0, 3)
	local body = if white then Palette.WhiteBody else Palette.Bezel
	local trim = if white then Palette.Steel else Color3.fromRGB(46, 48, 56)

	part(model, {
		Name = "Base",
		Size = Vector3.new(3.4, 0.3, 2.6),
		CFrame = at * CFrame.new(0, 0.15, 0),
		Color = trim,
	})
	if white then
		part(model, {
			Name = "Pedestal",
			Size = Vector3.new(2.6, 2.7, 0.9),
			CFrame = at * CFrame.new(0, 1.65, -0.1),
			Color = body,
		})
	else
		part(model, {
			Name = "Pole",
			Size = Vector3.new(0.55, 2.7, 0.55),
			CFrame = at * CFrame.new(0, 1.65, -0.1),
			Color = trim,
		})
	end
	local housing = part(model, {
		Name = "Housing",
		Size = Vector3.new(3.6, 6.2, 0.7),
		CFrame = facingCFrame((at * CFrame.new(0, 6.1, -0.1)).Position, FRONT),
		Color = body,
	})
	part(model, {
		Name = "Bezel",
		Size = Vector3.new(3.3, 4.7, 0.06),
		CFrame = housing.CFrame * CFrame.new(0, 0.6, -0.37),
		Color = Palette.Bezel,
		CanCollide = false,
	})
	part(model, {
		Name = "Screen",
		Size = Vector3.new(3.1, 4.5, 0.04),
		CFrame = housing.CFrame * CFrame.new(0, 0.6, -0.41),
		Color = Palette.Panel,
		CanCollide = false,
	})
	part(model, {
		Name = "CardReader",
		Size = Vector3.new(0.8, 1, 0.3),
		CFrame = housing.CFrame * CFrame.new(0.9, -2.3, -0.45),
		Color = trim,
	})
	part(model, {
		Name = "CardLight",
		Size = Vector3.new(0.5, 0.08, 0.05),
		CFrame = housing.CFrame * CFrame.new(0.9, -1.95, -0.62),
		Color = Palette.Success,
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	part(model, {
		Name = "ReceiptSlot",
		Size = Vector3.new(1.2, 0.08, 0.05),
		CFrame = housing.CFrame * CFrame.new(-0.7, -2.25, -0.37),
		Color = Palette.Accent,
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	model.PrimaryPart = housing
	model.Parent = world
	tag(model, Config.Tags.Kiosk, { KioskId = id, KioskName = "Kiosk " .. string.sub(id, 2) })
end

function Demo.buildRestaurant()
	local origin = Vector3.new(0, 0, -30)
	local base = CFrame.new(origin.X, groundY(origin.X, origin.Z), origin.Z)

	local world = Instance.new("Folder")
	world.Name = "RoPOS Demo"
	world.Parent = workspace

	buildRoom(world, base)
	local register = buildCounter(base)
	buildScreens(world, base, register)
	register.Parent = world
	tag(register, Config.Tags.Register)

	buildKiosk(world, base, 19, "K1", false)
	buildKiosk(world, base, 25, "K2", true)
end

local function buildTool(name: string, colour: Color3): Tool
	local tool = Instance.new("Tool")
	tool.Name = name
	tool.ToolTip = name
	tool.CanBeDropped = false
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.8, 1.1, 0.8)
	handle.Color = colour
	handle.Material = Enum.Material.SmoothPlastic
	handle.TopSurface = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	handle.Massless = true
	handle.Parent = tool
	return tool
end

function Demo.ensureItems()
	local folder = ServerStorage:FindFirstChild("POSItems")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "POSItems"
		folder.Parent = ServerStorage
	end
	for _, product in Config.Products do
		if product.Tool and not folder:FindFirstChild(product.Tool) then
			buildTool(product.Tool, product.Colour or Color3.new(1, 1, 1)).Parent = folder
		end
	end
end

function Demo.setup()
	if Config.Demo.SpawnRegister and #CollectionService:GetTagged(Config.Tags.Register) == 0 then
		Demo.buildRestaurant()
	end
	if Config.Demo.CreateItemTools then
		Demo.ensureItems()
	end
end

return Demo

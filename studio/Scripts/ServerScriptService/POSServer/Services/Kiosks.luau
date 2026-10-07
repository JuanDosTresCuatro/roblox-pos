-- Self-order kiosks. Tag a Model or Part "POSKiosk"; a Part named "Screen" inside it becomes
-- the touchscreen (the client draws it). One customer at a time: the server records who is
-- using each kiosk in the "Occupant" attribute, so every client can show "In use".
--
-- Optional attributes on the tagged instance: KioskId (string), KioskName (string).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("POS")
local Config = require(Shared.Config)
local Validate = require(Shared.Validate)
local Api = require(script.Parent.Api)
local Catalogue = require(script.Parent.Catalogue)
local Checkout = require(script.Parent.Checkout)
local Wallet = require(script.Parent.Wallet)

local Kiosks = {}

export type Kiosk = {
	id: string,
	name: string,
	instance: Instance,
	screen: BasePart,
	occupant: Player?,
	lastActive: number,
}

local kiosks: { [string]: Kiosk } = {}
local byInstance: { [Instance]: Kiosk } = {}
local count = 0

local function setOccupant(kiosk: Kiosk, player: Player?)
	kiosk.occupant = player
	kiosk.lastActive = os.clock()
	kiosk.instance:SetAttribute("Occupant", if player then player.UserId else 0)
end

local function distance(kiosk: Kiosk, player: Player): number
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return math.huge
	end
	return (root.Position - kiosk.screen.Position).Magnitude
end

local function get(id: any): Kiosk
	local kiosk = typeof(id) == "string" and kiosks[id]
	if not kiosk then
		Api.fail("Kiosk not found")
	end
	return kiosk
end

local function mine(player: Player, id: any): Kiosk
	local kiosk = get(id)
	if kiosk.occupant ~= player then
		Api.fail("This kiosk has been reset. Tap the screen to start again.")
	end
	kiosk.lastActive = os.clock()
	return kiosk
end

function Kiosks.release(kiosk: Kiosk, reason: string?)
	local player = kiosk.occupant
	if not player then
		return
	end
	setOccupant(kiosk, nil)
	if reason then
		Api.push(player, "KioskClosed", { id = kiosk.id, reason = reason })
	end
end

function Kiosks.start(player: Player, id: any)
	if not Config.Kiosk.Enabled then
		Api.fail("Kiosks are switched off")
	end
	local kiosk = get(id)
	if distance(kiosk, player) > Config.Kiosk.Range then
		Api.fail("Step closer to the kiosk")
	end
	if kiosk.occupant and kiosk.occupant ~= player and kiosk.occupant.Parent then
		Api.fail("Someone else is using this kiosk")
	end
	for _, other in kiosks do
		if other ~= kiosk and other.occupant == player then
			Kiosks.release(other, nil)
		end
	end
	setOccupant(kiosk, player)
	return {
		id = kiosk.id,
		name = kiosk.name,
		catalogue = Catalogue.list(),
		balance = Wallet.balance(player),
	}
end

function Kiosks.ping(player: Player, id: any)
	mine(player, id)
end

function Kiosks.cancel(player: Player, id: any)
	local kiosk = get(id)
	if kiosk.occupant == player then
		Kiosks.release(kiosk, nil)
	end
end

function Kiosks.checkout(player: Player, id: any, rawCart: any, rawDining: any, rawExpected: any)
	local kiosk = mine(player, id)
	if distance(kiosk, player) > Config.Kiosk.Range + 4 then
		Api.fail("Step closer to the kiosk")
	end
	local cart, problem = Validate.cart(rawCart, Config.Checkout.MaxLines, Config.Checkout.MaxQty)
	if not cart then
		Api.fail(problem or "Invalid order")
	end
	local dining = Checkout.dining(rawDining)
	if #Config.Orders.DiningOptions > 0 and not dining then
		Api.fail("Choose where you would like to eat")
	end
	local totals = Checkout.price(cart, 0)
	-- The screen showed a total; never charge a different one.
	if typeof(rawExpected) == "number" and rawExpected ~= totals.total then
		Api.fail("Prices have changed. Check your order and try again.")
	end
	local sale = Checkout.complete({
		customer = player,
		totals = totals,
		discountPct = 0,
		registerId = kiosk.id,
		registerName = kiosk.name,
		shift = nil,
		cashier = { userId = 0, name = kiosk.name },
		actor = kiosk.name,
		dining = dining,
		source = "Kiosk",
		onPaid = function()
			setOccupant(kiosk, nil)
		end,
	})
	if not sale then
		Api.fail("You don't have enough " .. Config.Currency.StatName)
	end
	return sale
end

local function findScreen(instance: Instance): BasePart?
	local screen = instance:FindFirstChild("Screen", true)
	if screen and screen:IsA("BasePart") then
		return screen
	end
	if instance:IsA("BasePart") then
		return instance
	end
	return instance:FindFirstChildWhichIsA("BasePart", true)
end

local function add(instance: Instance)
	if byInstance[instance] then
		return
	end
	local screen = findScreen(instance)
	if not screen then
		warn("[RoPOS] " .. instance:GetFullName() .. " is tagged " .. Config.Tags.Kiosk .. " but has no parts")
		return
	end
	count += 1
	local id = instance:GetAttribute("KioskId")
	if typeof(id) ~= "string" or id == "" or kiosks[id] then
		id = "K" .. count
		instance:SetAttribute("KioskId", id)
	end
	local name = instance:GetAttribute("KioskName")
	if typeof(name) ~= "string" or name == "" then
		name = "Kiosk " .. count
		instance:SetAttribute("KioskName", name)
	end
	local kiosk: Kiosk = { id = id, name = name, instance = instance, screen = screen, occupant = nil, lastActive = 0 }
	kiosks[id] = kiosk
	byInstance[instance] = kiosk
	setOccupant(kiosk, nil)
end

local function remove(instance: Instance)
	local kiosk = byInstance[instance]
	if kiosk then
		Kiosks.release(kiosk, "The kiosk was removed")
		kiosks[kiosk.id] = nil
		byInstance[instance] = nil
	end
end

function Kiosks.all(): { Kiosk }
	local out = {}
	for _, kiosk in kiosks do
		table.insert(out, kiosk)
	end
	return out
end

function Kiosks.init()
	for _, instance in CollectionService:GetTagged(Config.Tags.Kiosk) do
		add(instance)
	end
	CollectionService:GetInstanceAddedSignal(Config.Tags.Kiosk):Connect(add)
	CollectionService:GetInstanceRemovedSignal(Config.Tags.Kiosk):Connect(remove)

	Players.PlayerRemoving:Connect(function(player)
		for _, kiosk in kiosks do
			if kiosk.occupant == player then
				Kiosks.release(kiosk, nil)
			end
		end
	end)

	-- Free kiosks that were walked away from or left idle.
	task.spawn(function()
		while true do
			task.wait(1)
			for _, kiosk in kiosks do
				local player = kiosk.occupant
				if player then
					if not player.Parent then
						Kiosks.release(kiosk, nil)
					elseif distance(kiosk, player) > Config.Kiosk.Range + 6 then
						Kiosks.release(kiosk, "You walked away from the kiosk")
					elseif os.clock() - kiosk.lastActive > Config.Kiosk.IdleTimeout then
						Kiosks.release(kiosk, "The kiosk timed out")
					end
				end
			end
		end
	end)
end

return Kiosks

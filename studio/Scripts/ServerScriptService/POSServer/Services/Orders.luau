-- Order tickets for the kitchen display and the order status board.
--
-- Every paid sale (till or kiosk) gets an order number and a ticket that moves
-- preparing -> ready -> collected. Tickets live on this server only, because the kitchen,
-- the board and the customer waiting for their food are all in this server.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("POS")
local Config = require(Shared.Config)
local Signal = require(Shared.Signal)
local Api = require(script.Parent.Api)
local Audit = require(script.Parent.Audit)

local Orders = {}
Orders.changed = Signal.new()

export type Ticket = {
	number: number,
	receipt: string,
	source: string,
	dining: string?,
	customer: string,
	customerId: number,
	lines: { { name: string, qty: number } },
	status: "preparing" | "ready" | "collected",
	placedAt: number, -- os.time()
	readyAt: number?,
}

local MAX_NUMBER = 999

local tickets: { Ticket } = {} -- active (preparing or ready), oldest first
local lastNumber = 0
local queued = false

local function find(number: number): (Ticket?, number?)
	for index, ticket in tickets do
		if ticket.number == number then
			return ticket, index
		end
	end
	return nil, nil
end

local function announce()
	if queued then
		return
	end
	queued = true
	task.defer(function()
		queued = false
		Orders.changed:Fire()
		Api.pushWhere(function()
			return true
		end, "Orders", Orders.list())
	end)
end

-- The next order number, skipping any still on the board after the counter wraps.
function Orders.nextNumber(): number
	for _ = 1, MAX_NUMBER do
		lastNumber = lastNumber % MAX_NUMBER + 1
		if not find(lastNumber) then
			return lastNumber
		end
	end
	return lastNumber
end

function Orders.add(sale)
	if not Config.Orders.Enabled or not sale.orderNumber then
		return
	end
	local lines = {}
	for _, line in sale.lines do
		table.insert(lines, { name = line.name, qty = line.qty })
	end
	table.insert(tickets, {
		number = sale.orderNumber,
		receipt = sale.receipt,
		source = sale.source or "Counter",
		dining = sale.dining,
		customer = sale.customer.name,
		customerId = sale.customer.userId,
		lines = lines,
		status = "preparing",
		placedAt = os.time(),
		readyAt = nil,
	})
	announce()
end

function Orders.list(): { Ticket }
	local out = {}
	for _, ticket in tickets do
		table.insert(out, table.clone(ticket))
	end
	return out
end

local function remove(ticket: Ticket)
	local _, index = find(ticket.number)
	if index then
		table.remove(tickets, index)
	end
end

function Orders.markReady(number: number, by: Player): (boolean, string?)
	local ticket = find(number)
	if not ticket then
		return false, "Order " .. number .. " is not on the board"
	end
	if ticket.status == "ready" then
		return true
	end
	ticket.status = "ready"
	local readyAt = os.time()
	ticket.readyAt = readyAt
	Audit.log(by, "order.ready", string.format("Order %d (%s)", number, ticket.receipt))

	local customer = Players:GetPlayerByUserId(ticket.customerId)
	if customer then
		Api.push(customer, "OrderReady", { number = number, dining = ticket.dining })
	end

	-- Clear it from the board if nobody marks it collected.
	task.delay(Config.Orders.ReadyClearAfter, function()
		if ticket.status == "ready" and ticket.readyAt == readyAt then
			ticket.status = "collected"
			remove(ticket)
			announce()
		end
	end)
	announce()
	return true
end

function Orders.recall(number: number, by: Player): (boolean, string?)
	local ticket = find(number)
	if not ticket then
		return false, "Order " .. number .. " is not on the board"
	end
	ticket.status = "preparing"
	ticket.readyAt = nil
	Audit.log(by, "order.recall", string.format("Order %d back to preparing", number))
	announce()
	return true
end

function Orders.collect(number: number, by: Player): (boolean, string?)
	local ticket = find(number)
	if not ticket then
		return false, "Order " .. number .. " is not on the board"
	end
	ticket.status = "collected"
	remove(ticket)
	Audit.log(by, "order.collected", string.format("Order %d (%s)", number, ticket.receipt))
	announce()
	return true
end

-- When a sale is refunded, its ticket comes off the board.
function Orders.cancelReceipt(receipt: string)
	for _, ticket in table.clone(tickets) do
		if ticket.receipt == receipt then
			remove(ticket)
			announce()
		end
	end
end

return Orders

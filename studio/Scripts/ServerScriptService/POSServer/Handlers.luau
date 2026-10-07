-- Every client action, in one place. Roles are checked by the router before a handler runs.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("POS")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Roles = require(Shared.Roles)
local Validate = require(Shared.Validate)

local Services = script.Parent.Services
local Api = require(Services.Api)
local Audit = require(Services.Audit)
local Catalogue = require(Services.Catalogue)
local Checkout = require(Services.Checkout)
local Kiosks = require(Services.Kiosks)
local Orders = require(Services.Orders)
local Registers = require(Services.Registers)
local Reports = require(Services.Reports)
local Sales = require(Services.Sales)
local Shifts = require(Services.Shifts)
local Staff = require(Services.Staff)
local Store = require(Services.Store)
local Wallet = require(Services.Wallet)

local Cashier, Manager, Customer = Roles.Cashier, Roles.Manager, Roles.Customer

local function money(n: number): string
	return Format.money(n, Config.Currency.Symbol)
end

local function myRegister(player: Player): Registers.Register
	local register = Registers.of(player)
	if not register then
		Api.fail("Open a register first")
	end
	return register
end

local function product(id: any)
	local found = typeof(id) == "string" and Catalogue.get(id)
	if not found then
		Api.fail("Product not found")
	end
	return found
end

-- Session --------------------------------------------------------------------------------

Api.handle("session.hello", Customer, function(player)
	local role = Staff.roleOf(player)
	local register = Registers.of(player)
	return {
		role = role,
		roleName = Roles.name(role),
		maxDiscount = Staff.maxDiscount(player),
		persistent = Store.persistent,
		catalogue = Catalogue.list(),
		orders = Orders.list(),
		register = if register then Registers.summary(register) else nil,
	}
end)

-- Register -------------------------------------------------------------------------------

Api.handle("register.leave", Cashier, function(player)
	local register = Registers.of(player)
	if register then
		Registers.release(register, nil)
	end
end)

Api.handle("register.preview", Cashier, function(player, rawCart, rawDiscount)
	local register = myRegister(player)
	if register.order then
		return
	end
	local cart = Validate.cart(rawCart, Config.Checkout.MaxLines, Config.Checkout.MaxQty)
	local pct = math.min(Validate.int(rawDiscount, 0, 100) or 0, Staff.maxDiscount(player))
	if not cart then
		register.preview = nil
	else
		local ok, totals = pcall(Checkout.price, cart, pct)
		if ok then
			local items = 0
			for _, line in cart do
				items += line.qty
			end
			local lines = {}
			for _, line in totals.lines do
				table.insert(
					lines,
					{ name = line.name or line.productId, qty = line.qty, total = line.unitPrice * line.qty }
				)
			end
			register.preview = { items = items, total = totals.total, discount = totals.discount, lines = lines }
		end
	end
	Registers.updateDisplay(register)
end)

Api.handle("register.customers", Cashier, function(player)
	local register = myRegister(player)
	local nearby = {}
	for _, other in game:GetService("Players"):GetPlayers() do
		local distance = Registers.distance(register, other)
		if distance <= Config.Checkout.CustomerRange then
			table.insert(nearby, {
				userId = other.UserId,
				name = other.DisplayName,
				username = other.Name,
				isYou = other == player,
				distance = math.floor(distance + 0.5),
			})
		end
	end
	table.sort(nearby, function(a, b)
		if a.isYou ~= b.isYou then
			return not a.isYou
		end
		return a.distance < b.distance
	end)
	return nearby
end)

-- Shift ----------------------------------------------------------------------------------

Api.handle("shift.open", Cashier, function(player)
	local register = myRegister(player)
	if register.shift then
		Api.fail("A shift is already open on " .. register.name)
	end
	register.shift = Shifts.new(register.id, register.name, player)
	Audit.log(player, "shift.open", register.name)
	Registers.updateDisplay(register)
	return Registers.summary(register)
end)

Api.handle("shift.report", Cashier, function(player)
	return Registers.summary(myRegister(player))
end)

Api.handle("shift.close", Cashier, function(player)
	local register = myRegister(player)
	local shift = register.shift
	if not shift then
		Api.fail("No shift is open")
	end
	if register.order then
		Api.fail("Finish or cancel the waiting payment first")
	end
	local report = Shifts.close(shift, player.Name)
	register.shift = nil
	Audit.log(
		player,
		"shift.close",
		string.format("%s: %d sales, net %s", register.name, report.totals.count, money(report.net))
	)
	Registers.updateDisplay(register)
	return report
end)

-- Checkout -------------------------------------------------------------------------------

Api.handle("checkout.start", Cashier, function(player, cart, discount, customerId, dining)
	return Checkout.start(player, myRegister(player), cart, discount, customerId, dining)
end)

Api.handle("checkout.cancel", Cashier, function(player, orderId)
	Checkout.cancel(player, orderId)
end)

Api.handle("checkout.respond", Customer, function(player, orderId, accept)
	return Checkout.respond(player, orderId, accept)
end)

-- Sales ----------------------------------------------------------------------------------

Api.handle("sales.recent", Cashier, function(_player, limit)
	return Sales.recent(Validate.int(limit, 1, 200) or 50)
end)

Api.handle("sales.get", Cashier, function(_player, receipt)
	local id = Validate.text(receipt, 32)
	local sale = id and Sales.get(string.upper(id))
	if not sale then
		Api.fail("Receipt not found")
	end
	return sale
end)

Api.handle("sales.refund", Manager, function(player, receipt, restock)
	local id = Validate.text(receipt, 32)
	local sale = id and Sales.get(id)
	if not sale then
		Api.fail("Receipt not found")
	end
	if sale.refunded then
		Api.fail("This sale has already been refunded")
	end
	restock = restock == true

	local updated, problem = Sales.markRefunded(sale.receipt, player.Name, restock)
	if not updated then
		Api.fail(problem or "Refund failed")
	end
	local credited, creditProblem = Wallet.creditUserId(sale.customer.userId, sale.total)
	if not credited then
		Sales.unmarkRefunded(sale.receipt)
		Api.fail(creditProblem or "Could not return the money. Nothing was refunded.")
	end

	if restock then
		for _, line in sale.lines do
			Catalogue.adjustStock(line.productId, line.qty)
		end
	end
	Reports.recordRefund(sale, os.time())
	Orders.cancelReceipt(sale.receipt)
	local register = Registers.of(player)
	if register and register.shift then
		Shifts.recordRefund(register.shift, sale)
		Registers.refreshOperator(register)
	end
	Audit.log(
		player,
		"refund",
		string.format(
			"%s: %s to %s%s",
			sale.receipt,
			money(sale.total),
			sale.customer.name,
			if restock then ", restocked" else ""
		)
	)

	local customer = game:GetService("Players"):GetPlayerByUserId(sale.customer.userId)
	if customer then
		Api.toast(customer, string.format("You were refunded %s for %s", money(sale.total), sale.receipt), "success")
	end
	return updated
end)

-- Products (manager) ---------------------------------------------------------------------

Api.handle("products.price", Manager, function(player, id, price)
	local item = product(id)
	local value = Validate.int(price, 0, 1e9)
	if not value then
		Api.fail("Enter a whole number price")
	end
	if value ~= item.price then
		Audit.log(player, "product.price", string.format("%s: %s -> %s", item.name, money(item.price), money(value)))
		Catalogue.setPrice(item.id, value)
	end
end)

Api.handle("products.stock", Manager, function(player, id, delta)
	local item = product(id)
	local change = Validate.int(delta, -1e6, 1e6)
	if not change or change == 0 then
		Api.fail("Invalid stock change")
	end
	if item.stock == nil then
		Api.fail(item.name .. " is not stock-tracked")
	end
	Audit.log(player, "stock.adjust", string.format("%s: %+d (was %d)", item.name, change, item.stock))
	Catalogue.adjustStock(item.id, change)
end)

Api.handle("products.active", Manager, function(player, id, active)
	local item = product(id)
	if typeof(active) ~= "boolean" then
		Api.fail("Invalid value")
	end
	Audit.log(player, "product.active", item.name .. (if active then " on sale" else " taken off sale"))
	Catalogue.setActive(item.id, active)
end)

-- Reports and audit (manager) ------------------------------------------------------------

Api.handle("reports.days", Manager, function(_player, count)
	return Reports.days(Validate.int(count, 1, 14) or 7)
end)

Api.handle("audit.recent", Manager, function(_player, limit)
	return Audit.recent(Validate.int(limit, 1, 500) or 100)
end)

-- Kiosks (customers) ---------------------------------------------------------------------

Api.handle("kiosk.start", Customer, function(player, id)
	return Kiosks.start(player, id)
end)

Api.handle("kiosk.ping", Customer, function(player, id)
	Kiosks.ping(player, id)
end)

Api.handle("kiosk.cancel", Customer, function(player, id)
	Kiosks.cancel(player, id)
end)

Api.handle("kiosk.checkout", Customer, function(player, id, cart, dining, expectedTotal)
	return Kiosks.checkout(player, id, cart, dining, expectedTotal)
end)

-- Orders (kitchen display and the Orders tab) --------------------------------------------

local function orderNumber(raw: any): number
	local number = Validate.int(raw, 1, 999)
	if not number then
		Api.fail("Invalid order number")
	end
	return number
end

local function orderAction(fn: (number, Player) -> (boolean, string?))
	return function(player, raw)
		local ok, problem = fn(orderNumber(raw), player)
		if not ok then
			Api.fail(problem or "That order is not on the board")
		end
	end
end

Api.handle("orders.list", Customer, function()
	return Orders.list()
end)
Api.handle("orders.ready", Cashier, orderAction(Orders.markReady))
Api.handle("orders.recall", Cashier, orderAction(Orders.recall))
Api.handle("orders.collect", Cashier, orderAction(Orders.collect))

-- Keep every screen in step with the catalogue. Menus, kiosks and tills all show it.
Catalogue.changed:Connect(function()
	local snapshot = Catalogue.list()
	Api.pushWhere(function()
		return true
	end, "Catalogue", snapshot)
end)

return {}

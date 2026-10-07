-- The self-order kiosk touchscreen. Each player draws every kiosk on their own screen
-- (a SurfaceGui in PlayerGui adorned to the kiosk's Screen part), so taps are theirs.
--
-- Steps: start -> where would you like to eat? -> menu -> your order -> pay -> order number.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("POS")
local Config = require(Shared.Config)
local Format = require(Shared.Format)
local Pricing = require(Shared.Pricing)

local Client = script.Parent.Parent
local Api = require(Client.Api)
local State = require(Client.State)
local UI = require(Client.UI.UI)
local Theme = require(Client.UI.Theme)
local Toasts = require(Client.UI.Toasts)

local C, F = Theme.Colors, Theme.Fonts

local Kiosk = {}

local CANVAS = Vector2.new(620, 900)
local PING_EVERY = 8
local DINING_ICONS = { ["Eat in"] = "🍽", ["Take away"] = "🛍" }

local player = Players.LocalPlayer
local kiosks = {}

local function money(n: number): string
	return Format.money(n, Config.Currency.Symbol)
end

local function balance(): number?
	local leaderstats = player:FindFirstChild("leaderstats")
	local stat = leaderstats and leaderstats:FindFirstChild(Config.Currency.StatName)
	return if stat and (stat:IsA("IntValue") or stat:IsA("NumberValue")) then stat.Value else nil
end

local function big(props)
	props.TextSize = props.TextSize or 30
	props.Radius = props.Radius or Theme.Radius.Large
	return UI.button(props)
end

local function mount(instance: Instance)
	local screen = instance:FindFirstChild("Screen", true)
	if not screen or not screen:IsA("BasePart") or kiosks[instance] then
		return
	end

	local self = {
		id = instance:GetAttribute("KioskId"),
		name = instance:GetAttribute("KioskName") or "Kiosk",
		step = "start",
		dining = nil :: string?,
		category = Config.Categories[1],
		cart = {} :: { { productId: string, qty: number } },
		lastPing = 0,
		lastTap = 0,
		done = nil :: any,
	}
	kiosks[instance] = self

	local gui = UI.new("SurfaceGui", {
		Name = "RoPOSKiosk",
		Adornee = screen,
		Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
		CanvasSize = CANVAS,
		LightInfluence = 0,
		Brightness = 1.3,
		MaxDistance = 40,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local root = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Panel, Parent = gui })

	local render -- forward

	local function occupiedByOther(): boolean
		local occupant = instance:GetAttribute("Occupant")
		return typeof(occupant) == "number" and occupant ~= 0 and occupant ~= player.UserId
	end

	local function reset()
		self.step = "start"
		self.dining = nil
		self.cart = {}
		self.category = Config.Categories[1]
		render()
	end

	-- Every tap keeps the kiosk ours; the server frees it after Config.Kiosk.IdleTimeout.
	local function tap()
		self.lastTap = os.clock()
		if self.step ~= "start" and os.clock() - self.lastPing > PING_EVERY then
			self.lastPing = os.clock()
			task.spawn(Api.call, "kiosk.ping", self.id)
		end
	end

	local function go(step: string)
		tap()
		self.step = step
		render()
	end

	local function cancel()
		Api.call("kiosk.cancel", self.id)
		reset()
	end

	local function totals(): Pricing.Totals
		local lines = {}
		for _, line in self.cart do
			local product = State.byId[line.productId]
			if product and product.active then
				table.insert(lines, {
					productId = product.id,
					name = product.name,
					unitPrice = product.price,
					qty = line.qty,
					taxRate = if Config.Tax.Enabled then product.taxRate else 0,
				})
			end
		end
		return Pricing.priceLines(lines, { discountPct = 0, taxInclusive = Config.Tax.Inclusive })
	end

	local function qtyIn(id: string): number
		for _, line in self.cart do
			if line.productId == id then
				return line.qty
			end
		end
		return 0
	end

	local function setQty(id: string, qty: number)
		tap()
		local product = State.byId[id]
		if not product then
			return
		end
		if product.stock ~= nil and qty > product.stock then
			Toasts.show(string.format("Only %d %s left", product.stock, product.name), "warning")
			return
		end
		if qty > Config.Checkout.MaxQty then
			return
		end
		for i, line in self.cart do
			if line.productId == id then
				if qty <= 0 then
					table.remove(self.cart, i)
				else
					line.qty = qty
				end
				render()
				return
			end
		end
		if qty > 0 and #self.cart < Config.Checkout.MaxLines then
			table.insert(self.cart, { productId = id, qty = qty })
		end
		render()
	end

	local function start()
		tap()
		local ok, result = Api.call("kiosk.start", self.id)
		if not ok then
			Toasts.show(result, "warning")
			return
		end
		State.set("catalogue", result.catalogue)
		self.lastPing = os.clock()
		go(if #Config.Orders.DiningOptions > 0 then "dining" else "menu")
	end

	local function pay()
		local t = totals()
		self.step = "paying"
		render()
		local ok, result = Api.call("kiosk.checkout", self.id, self.cart, self.dining, t.total)
		if ok then
			self.done = result
			self.step = "done"
			render()
			local finished = result
			task.delay(12, function()
				if self.done == finished and self.step == "done" then
					reset()
				end
			end)
		else
			Toasts.show(result, "error")
			self.step = "basket"
			render()
		end
	end

	-- Shared pieces ---------------------------------------------------------------

	local function topBar(parent: Instance, title: string)
		local bar = UI.new("Frame", {
			BackgroundColor3 = C.Accent,
			Size = UDim2.new(1, 0, 0, 92),
			Parent = parent,
		})
		UI.text({
			Text = Config.Store.Name,
			FontFace = F.Heavy,
			TextSize = 30,
			TextColor3 = C.OnAccent,
			Position = UDim2.fromOffset(28, 14),
			Size = UDim2.new(1, -170, 0, 34),
			Parent = bar,
		})
		UI.text({
			Text = title,
			FontFace = F.Medium,
			TextSize = 20,
			TextColor3 = C.OnAccent,
			Position = UDim2.fromOffset(28, 50),
			Size = UDim2.new(1, -170, 0, 26),
			Parent = bar,
		})
		UI.button({
			Text = "Cancel",
			Style = "dark",
			TextSize = 20,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -22, 0.5, 0),
			Size = UDim2.fromOffset(120, 52),
			Radius = Theme.Radius.Pill,
			Parent = bar,
			OnClick = cancel,
		})
		return bar
	end

	-- Steps ------------------------------------------------------------------------

	local function drawStart()
		UI.new("Frame", {
			BackgroundColor3 = C.Accent,
			Size = UDim2.fromScale(1, 0.46),
			Parent = root,
			Children = {
				UI.text({
					Text = Config.Store.Name,
					FontFace = F.Heavy,
					TextSize = 64,
					TextColor3 = C.OnAccent,
					TextXAlignment = Enum.TextXAlignment.Center,
					Position = UDim2.fromScale(0, 0.3),
					Size = UDim2.new(1, 0, 0, 76),
				}),
				UI.text({
					Text = "Order and pay here",
					FontFace = F.Medium,
					TextSize = 30,
					TextColor3 = C.OnAccent,
					TextXAlignment = Enum.TextXAlignment.Center,
					Position = UDim2.fromScale(0, 0.58),
					Size = UDim2.new(1, 0, 0, 40),
				}),
			},
		})
		if occupiedByOther() then
			UI.text({
				Text = "Someone is ordering",
				FontFace = F.Heavy,
				TextSize = 40,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromScale(0, 0.58),
				Size = UDim2.new(1, 0, 0, 50),
				Parent = root,
			})
			UI.text({
				Text = "Please wait or use another kiosk",
				TextColor3 = C.Muted,
				TextSize = 26,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromScale(0, 0.66),
				Size = UDim2.new(1, 0, 0, 34),
				Parent = root,
			})
			return
		end
		local button = big({
			Text = "Touch to start",
			Style = "primary",
			TextSize = 36,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.6),
			Size = UDim2.new(0.8, 0, 0, 110),
			Parent = root,
			OnClick = start,
		})
		-- A gentle pulse so the kiosk looks alive from across the room.
		local scale = button:FindFirstChildOfClass("UIScale")
		task.spawn(function()
			while button.Parent and scale do
				UI.tween(scale, { Scale = 1.04 }, TweenInfo.new(0.9, Enum.EasingStyle.Sine))
				task.wait(0.9)
				UI.tween(scale, { Scale = 1 }, TweenInfo.new(0.9, Enum.EasingStyle.Sine))
				task.wait(0.9)
			end
		end)
		UI.text({
			Text = string.format("Pay with your %s · %s", Config.Currency.StatName, self.name),
			TextColor3 = C.Faint,
			TextSize = 22,
			TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, -30),
			Size = UDim2.new(1, 0, 0, 30),
			Parent = root,
		})
	end

	local function drawDining()
		topBar(root, "Step 1 of 3")
		UI.text({
			Text = "Where would you like to eat?",
			FontFace = F.Heavy,
			TextSize = 40,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(30, 170),
			Size = UDim2.new(1, -60, 0, 110),
			Parent = root,
		})
		local options = Config.Orders.DiningOptions
		for i, option in options do
			local card = UI.new("TextButton", {
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = C.Raised,
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new((i - 0.5) / #options, 0, 0, 330),
				Size = UDim2.new(1 / #options, -40, 0, 300),
				Parent = root,
				Children = {
					UI.corner(Theme.Radius.Large),
					UI.stroke(C.Border, 2),
					UI.text({
						Text = DINING_ICONS[option] or "•",
						TextSize = 110,
						TextXAlignment = Enum.TextXAlignment.Center,
						Position = UDim2.fromOffset(0, 40),
						Size = UDim2.new(1, 0, 0, 140),
					}),
					UI.text({
						Text = option,
						FontFace = F.Heavy,
						TextSize = 34,
						TextXAlignment = Enum.TextXAlignment.Center,
						Position = UDim2.fromOffset(0, 210),
						Size = UDim2.new(1, 0, 0, 44),
					}),
				},
			})
			card.MouseEnter:Connect(function()
				UI.tween(card, { BackgroundColor3 = C.AccentSoft })
			end)
			card.MouseLeave:Connect(function()
				UI.tween(card, { BackgroundColor3 = C.Raised })
			end)
			card.Activated:Connect(function()
				self.dining = option
				go("menu")
			end)
		end
	end

	local function drawMenu()
		topBar(root, (if self.dining then self.dining .. " · " else "") .. "Choose your items")

		-- Category rail
		local rail = UI.new("Frame", {
			BackgroundColor3 = C.Raised,
			Position = UDim2.fromOffset(0, 92),
			Size = UDim2.new(0, 170, 1, -92 - 120),
			Parent = root,
			Children = { UI.padding(14, 12), UI.list(10) },
		})
		for i, category in Config.Categories do
			local selected = category == self.category
			local chip = UI.button({
				Text = category,
				Style = if selected then "primary" else "ghost",
				TextSize = 22,
				Size = UDim2.new(1, 0, 0, 64),
				LayoutOrder = i,
				Radius = Theme.Radius.Medium,
				Parent = rail,
				OnClick = function()
					self.category = category
					go("menu")
				end,
			})
			chip.TextWrapped = true
		end

		-- Item grid
		local grid = UI.scroll({
			Position = UDim2.fromOffset(170, 92),
			Size = UDim2.new(1, -170, 1, -92 - 120),
			ScrollBarThickness = 8,
			Parent = root,
			Children = {
				UI.padding(16),
				UI.new("UIGridLayout", {
					CellSize = UDim2.new(0.5, -8, 0, 250),
					CellPadding = UDim2.fromOffset(16, 16),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
			},
		})
		for index, product in State.catalogue do
			if product.active and product.category == self.category then
				local soldOut = product.stock ~= nil and product.stock <= 0
				local qty = qtyIn(product.id)
				local stroke = UI.stroke(if qty > 0 then C.Accent else C.Border, if qty > 0 then 3 else 1)
				local card = UI.new("TextButton", {
					Text = "",
					AutoButtonColor = false,
					BackgroundColor3 = C.Panel,
					LayoutOrder = index,
					Parent = grid,
					Children = {
						UI.corner(Theme.Radius.Large),
						stroke,
						UI.new("Frame", {
							BackgroundColor3 = product.colour,
							BackgroundTransparency = if soldOut then 0.6 else 0,
							AnchorPoint = Vector2.new(0.5, 0),
							Position = UDim2.new(0.5, 0, 0, 22),
							Size = UDim2.fromOffset(100, 100),
							Children = {
								UI.corner(Theme.Radius.Pill),
								UI.text({
									Text = string.upper(string.sub(product.name, 1, 1)),
									FontFace = F.Heavy,
									TextSize = 46,
									TextColor3 = C.Panel,
									TextXAlignment = Enum.TextXAlignment.Center,
									Size = UDim2.fromScale(1, 1),
								}),
							},
						}),
						UI.text({
							Text = product.name,
							FontFace = F.Bold,
							TextSize = 24,
							TextWrapped = true,
							TextColor3 = if soldOut then C.Faint else C.Text,
							TextXAlignment = Enum.TextXAlignment.Center,
							Position = UDim2.fromOffset(10, 134),
							Size = UDim2.new(1, -20, 0, 56),
						}),
						UI.text({
							Text = if soldOut then "Sold out" else money(product.price),
							FontFace = F.Heavy,
							TextSize = 26,
							TextColor3 = if soldOut then C.Danger else C.AccentText,
							TextXAlignment = Enum.TextXAlignment.Center,
							Position = UDim2.fromOffset(0, 196),
							Size = UDim2.new(1, 0, 0, 32),
						}),
						if qty > 0
							then UI.pill("×" .. qty, C.OnAccent, C.Accent, {
								AnchorPoint = Vector2.new(1, 0),
								Position = UDim2.new(1, -12, 0, 12),
								Size = UDim2.fromOffset(0, 34),
							})
							else nil,
					},
				})
				card.Activated:Connect(function()
					if not soldOut then
						setQty(product.id, qtyIn(product.id) + 1)
					end
				end)
			end
		end

		-- Order bar
		local t = totals()
		local items = 0
		for _, line in t.lines do
			items += line.qty
		end
		local bar = UI.new("Frame", {
			BackgroundColor3 = C.Panel,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 120),
			Parent = root,
			Children = { UI.stroke(C.Border, 1) },
		})
		UI.text({
			Text = if items > 0
				then string.format("Your order · %d item%s", items, if items == 1 then "" else "s")
				else "Your order is empty",
			TextSize = 22,
			TextColor3 = C.Muted,
			Position = UDim2.fromOffset(28, 22),
			Size = UDim2.new(0.5, 0, 0, 28),
			Parent = bar,
		})
		UI.text({
			Text = money(t.total),
			FontFace = F.Heavy,
			TextSize = 40,
			Position = UDim2.fromOffset(28, 54),
			Size = UDim2.new(0.5, 0, 0, 46),
			Parent = bar,
		})
		local view = big({
			Text = "View order",
			Style = "primary",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -24, 0.5, 0),
			Size = UDim2.fromOffset(250, 80),
			Parent = bar,
			OnClick = function()
				go("basket")
			end,
		})
		if items == 0 then
			UI.setEnabled(view, false)
		end
	end

	local function drawBasket()
		topBar(
			root,
			"Step " .. (if #Config.Orders.DiningOptions > 0 then "3 of 3" else "2 of 2") .. " · Check your order"
		)
		local t = totals()
		local list = UI.scroll({
			Position = UDim2.fromOffset(0, 92),
			Size = UDim2.new(1, 0, 1, -92 - 300),
			ScrollBarThickness = 8,
			Parent = root,
			Children = { UI.padding(20, 24), UI.list(12) },
		})
		for i, line in t.lines do
			local product = State.byId[line.productId]
			local row = UI.new("Frame", {
				BackgroundColor3 = C.Raised,
				Size = UDim2.new(1, 0, 0, 96),
				LayoutOrder = i,
				Parent = list,
				Children = {
					UI.corner(Theme.Radius.Medium),
					UI.new("Frame", {
						BackgroundColor3 = if product then product.colour else C.Accent,
						Position = UDim2.new(0, 16, 0.5, -26),
						Size = UDim2.fromOffset(52, 52),
						Children = { UI.corner(Theme.Radius.Pill) },
					}),
					UI.text({
						Text = line.name or line.productId,
						FontFace = F.Bold,
						TextSize = 24,
						Position = UDim2.fromOffset(84, 16),
						Size = UDim2.new(1, -330, 0, 30),
					}),
					UI.text({
						Text = money(line.unitPrice) .. " each",
						TextSize = 19,
						TextColor3 = C.Muted,
						Position = UDim2.fromOffset(84, 50),
						Size = UDim2.new(1, -330, 0, 26),
					}),
					UI.text({
						Text = money(line.unitPrice * line.qty),
						FontFace = F.Heavy,
						TextSize = 24,
						TextXAlignment = Enum.TextXAlignment.Right,
						AnchorPoint = Vector2.new(1, 0.5),
						Position = UDim2.new(1, -16, 0.5, 0),
						Size = UDim2.fromOffset(90, 30),
					}),
				},
			})
			local stepper = UI.new("Frame", {
				BackgroundColor3 = C.Panel,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -116, 0.5, 0),
				Size = UDim2.fromOffset(150, 56),
				Parent = row,
				Children = { UI.corner(Theme.Radius.Pill), UI.stroke(C.Border) },
			})
			UI.button({
				Text = "−",
				Style = "ghost",
				TextSize = 30,
				Size = UDim2.fromOffset(52, 56),
				Radius = Theme.Radius.Pill,
				Parent = stepper,
				OnClick = function()
					setQty(line.productId, line.qty - 1)
				end,
			})
			UI.text({
				Text = tostring(line.qty),
				FontFace = F.Heavy,
				TextSize = 26,
				TextXAlignment = Enum.TextXAlignment.Center,
				Position = UDim2.fromOffset(52, 0),
				Size = UDim2.fromOffset(46, 56),
				Parent = stepper,
			})
			UI.button({
				Text = "+",
				Style = "ghost",
				TextSize = 30,
				Position = UDim2.fromOffset(98, 0),
				Size = UDim2.fromOffset(52, 56),
				Radius = Theme.Radius.Pill,
				Parent = stepper,
				OnClick = function()
					setQty(line.productId, line.qty + 1)
				end,
			})
		end
		if #t.lines == 0 then
			go("menu")
			return
		end

		local panel = UI.new("Frame", {
			BackgroundColor3 = C.Panel,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 300),
			Parent = root,
			Children = { UI.stroke(C.Border) },
		})
		local wallet = balance()
		local enough = wallet ~= nil and wallet >= t.total
		UI.text({
			Text = "Total",
			FontFace = F.Bold,
			TextSize = 30,
			Position = UDim2.fromOffset(28, 22),
			Size = UDim2.new(0.5, 0, 0, 40),
			Parent = panel,
		})
		UI.text({
			Text = money(t.total),
			FontFace = F.Heavy,
			TextSize = 46,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -28, 0, 16),
			Size = UDim2.new(0.5, 0, 0, 52),
			Parent = panel,
		})
		UI.text({
			Text = if wallet
				then string.format(
					"Your %s: %s → %s",
					Config.Currency.StatName,
					money(wallet),
					money(wallet - t.total)
				)
				else "Loading your balance…",
			TextSize = 20,
			TextColor3 = if enough then C.Muted else C.Danger,
			Position = UDim2.fromOffset(28, 76),
			Size = UDim2.new(1, -56, 0, 26),
			Parent = panel,
		})
		big({
			Text = "Add more",
			Style = "secondary",
			Position = UDim2.fromOffset(24, 130),
			Size = UDim2.new(0.38, -24, 0, 120),
			Parent = panel,
			OnClick = function()
				go("menu")
			end,
		})
		local payButton = big({
			Text = if enough then "Pay " .. money(t.total) else "Not enough " .. Config.Currency.StatName,
			Style = "success",
			TextSize = 34,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -24, 0, 130),
			Size = UDim2.new(0.62, -24, 0, 120),
			Parent = panel,
			OnClick = pay,
		})
		if not enough then
			UI.setEnabled(payButton, false)
		end
	end

	local function drawPaying()
		UI.text({
			Text = "Paying…",
			FontFace = F.Heavy,
			TextSize = 48,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromScale(0, 0.42),
			Size = UDim2.new(1, 0, 0, 60),
			Parent = root,
		})
		UI.text({
			Text = "Taking " .. money(totals().total) .. " from your " .. Config.Currency.StatName,
			TextColor3 = C.Muted,
			TextSize = 24,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.new(1, 0, 0, 34),
			Parent = root,
		})
	end

	local function drawDone()
		local sale = self.done
		UI.new("Frame", {
			BackgroundColor3 = C.Success,
			Size = UDim2.fromScale(1, 0.4),
			Parent = root,
			Children = {
				UI.text({
					Text = "✓",
					FontFace = F.Heavy,
					TextSize = 110,
					TextColor3 = C.OnSuccess,
					TextXAlignment = Enum.TextXAlignment.Center,
					Position = UDim2.fromScale(0, 0.18),
					Size = UDim2.new(1, 0, 0, 120),
				}),
				UI.text({
					Text = "Thank you, " .. player.DisplayName .. "!",
					FontFace = F.Heavy,
					TextSize = 34,
					TextColor3 = C.OnSuccess,
					TextXAlignment = Enum.TextXAlignment.Center,
					Position = UDim2.fromScale(0, 0.68),
					Size = UDim2.new(1, 0, 0, 44),
				}),
			},
		})
		UI.text({
			Text = "Your order number",
			TextColor3 = C.Muted,
			TextSize = 28,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromScale(0, 0.45),
			Size = UDim2.new(1, 0, 0, 36),
			Parent = root,
		})
		UI.text({
			Text = if sale.orderNumber then tostring(sale.orderNumber) else sale.receipt,
			FontFace = F.Heavy,
			TextSize = 170,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.new(1, 0, 0, 190),
			Parent = root,
		})
		UI.text({
			Text = (if sale.dining then sale.dining .. " · " else "") .. "Watch the board for your number",
			TextColor3 = C.Muted,
			TextSize = 24,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromScale(0, 0.74),
			Size = UDim2.new(1, 0, 0, 32),
			Parent = root,
		})
		big({
			Text = "Done",
			Style = "primary",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -40),
			Size = UDim2.new(0.6, 0, 0, 90),
			Parent = root,
			OnClick = reset,
		})
	end

	function render()
		UI.clear(root)
		if self.step ~= "start" and self.step ~= "done" and occupiedByOther() then
			self.step = "start"
		end
		local draw = ({
			start = drawStart,
			dining = drawDining,
			menu = drawMenu,
			basket = drawBasket,
			paying = drawPaying,
			done = drawDone,
		})[self.step]
		draw()
	end

	function self.closed(reason: string?)
		if self.step ~= "start" and self.step ~= "done" then
			if reason then
				Toasts.show(reason, "info")
			end
			reset()
		end
	end

	function self.refresh()
		if self.step == "menu" or self.step == "basket" then
			render()
		end
	end

	instance:GetAttributeChangedSignal("Occupant"):Connect(function()
		if self.step == "start" then
			render()
		end
	end)

	-- Back to the start screen when left alone (the server frees the kiosk too).
	task.spawn(function()
		while gui.Parent do
			task.wait(2)
			if
				self.step ~= "start"
				and self.step ~= "done"
				and self.step ~= "paying"
				and os.clock() - self.lastTap > Config.Kiosk.IdleTimeout
			then
				cancel()
			end
		end
	end)

	render()
end

function Kiosk.mount()
	if not Config.Kiosk.Enabled then
		return
	end
	for _, instance in CollectionService:GetTagged(Config.Tags.Kiosk) do
		task.spawn(mount, instance)
	end
	CollectionService:GetInstanceAddedSignal(Config.Tags.Kiosk):Connect(function(instance)
		task.spawn(mount, instance)
	end)

	Api.on("KioskClosed", function(payload)
		for instance, kiosk in kiosks do
			if kiosk.id == payload.id or instance:GetAttribute("KioskId") == payload.id then
				kiosk.closed(payload.reason)
			end
		end
	end)
	State.changed:Connect(function(key)
		if key == "catalogue" then
			for _, kiosk in kiosks do
				kiosk.refresh()
			end
		end
	end)
end

return Kiosk

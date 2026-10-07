-- Orders: the same tickets as the kitchen display, for staff at the till or on a phone.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("POS")
local Config = require(Shared.Config)

local Client = script.Parent.Parent
local Api = require(Client.Api)
local State = require(Client.State)
local UI = require(Client.UI.UI)
local Theme = require(Client.UI.Theme)
local Toasts = require(Client.UI.Toasts)

local C, F = Theme.Colors, Theme.Fonts

local Orders = {}

local function act(action: string, number: number)
	local ok, err = Api.call(action, number)
	if not ok then
		Toasts.show(err, "error")
	end
end

function Orders.new(_ctx)
	local self = {}
	local frame = UI.new("Frame", { Name = "Orders", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
	self.frame = frame

	UI.text({ Text = "Orders", TextSize = 24, FontFace = F.Heavy, Size = UDim2.new(0.5, 0, 0, 30), Parent = frame })
	UI.text({
		Text = "Mark orders ready when they are made, and collected when the customer has them.",
		TextSize = 14,
		TextColor3 = C.Muted,
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 0, 18),
		Parent = frame,
	})
	local list = UI.scroll({
		Position = UDim2.fromOffset(0, 62),
		Size = UDim2.new(1, 0, 1, -62),
		Parent = frame,
		Children = { UI.list(8) },
	})

	local function render()
		UI.clear(list)
		if #State.orders == 0 then
			UI.text({ Text = "No orders waiting", TextColor3 = C.Faint, Parent = list })
		end
		for i, ticket in State.orders do
			local isReady = ticket.status == "ready"
			local items = {}
			for _, line in ticket.lines do
				table.insert(items, line.qty .. " × " .. line.name)
			end
			local minutes = math.max(0, os.time() - ticket.placedAt) // 60
			local row = UI.card({
				Size = UDim2.new(1, -8, 0, 64),
				LayoutOrder = i,
				Parent = list,
				Children = {
					UI.text({
						Text = "#" .. ticket.number,
						FontFace = F.Heavy,
						TextSize = 26,
						TextColor3 = if isReady then C.Success else C.Text,
						Position = UDim2.fromOffset(16, 0),
						Size = UDim2.new(0, 80, 1, 0),
					}),
					UI.text({
						Text = table.concat(items, ", "),
						FontFace = F.Bold,
						TextSize = 15,
						Position = UDim2.fromOffset(100, 12),
						Size = UDim2.new(1, -380, 0, 20),
					}),
					UI.text({
						Text = string.format(
							"%s · %s%s · %d min",
							ticket.customer,
							ticket.source,
							if ticket.dining then " · " .. ticket.dining else "",
							minutes
						),
						TextSize = 13,
						TextColor3 = C.Muted,
						Position = UDim2.fromOffset(100, 34),
						Size = UDim2.new(1, -380, 0, 18),
					}),
					if isReady
						then UI.pill("Ready", C.Success, C.SuccessSoft, {
							AnchorPoint = Vector2.new(1, 0.5),
							Position = UDim2.new(1, -264, 0.5, 0),
						})
						else UI.pill("Preparing", C.AccentText, C.AccentSoft, {
							AnchorPoint = Vector2.new(1, 0.5),
							Position = UDim2.new(1, -264, 0.5, 0),
						}),
				},
			})
			local actions = UI.new("Frame", {
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
				Size = UDim2.fromOffset(240, 40),
				Parent = row,
				Children = {
					UI.list(8, Enum.FillDirection.Horizontal, { HorizontalAlignment = Enum.HorizontalAlignment.Right }),
				},
			})
			if isReady then
				UI.button({
					Text = "Recall",
					Style = "ghost",
					Size = UDim2.fromOffset(90, 40),
					LayoutOrder = 1,
					Parent = actions,
					OnClick = function()
						act("orders.recall", ticket.number)
					end,
				})
				UI.button({
					Text = "Collected",
					Style = "primary",
					Size = UDim2.fromOffset(120, 40),
					LayoutOrder = 2,
					Parent = actions,
					OnClick = function()
						act("orders.collect", ticket.number)
					end,
				})
			else
				UI.button({
					Text = "Ready",
					Style = "success",
					Size = UDim2.fromOffset(120, 40),
					LayoutOrder = 2,
					Parent = actions,
					OnClick = function()
						act("orders.ready", ticket.number)
					end,
				})
			end
		end
	end

	State.changed:Connect(function(key)
		if key == "orders" and frame.Visible then
			render()
		end
	end)

	self.show = render
	if not Config.Orders.Enabled then
		self.hidden = true
	end
	return self
end

return Orders

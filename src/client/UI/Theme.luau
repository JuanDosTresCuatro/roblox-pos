-- Design tokens. Change these to restyle the whole POS.

local Theme = {}

-- Colours come from the shared palette so the POS window, kiosks and world screens match.
Theme.Colors = require(game:GetService("ReplicatedStorage"):WaitForChild("POS"):WaitForChild("Palette"))

local family = "rbxasset://fonts/families/BuilderSans.json"
local mono = "rbxasset://fonts/families/RobotoMono.json"

Theme.Fonts = {
	Regular = Font.new(family, Enum.FontWeight.Regular),
	Medium = Font.new(family, Enum.FontWeight.Medium),
	Bold = Font.new(family, Enum.FontWeight.Bold),
	Heavy = Font.new(family, Enum.FontWeight.ExtraBold),
	Mono = Font.new(mono, Enum.FontWeight.Regular),
	MonoBold = Font.new(mono, Enum.FontWeight.Bold),
}

Theme.Radius = {
	Small = UDim.new(0, 8),
	Medium = UDim.new(0, 12),
	Large = UDim.new(0, 16),
	Pill = UDim.new(1, 0),
}

Theme.Tween = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
Theme.TweenSlow = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

return Theme

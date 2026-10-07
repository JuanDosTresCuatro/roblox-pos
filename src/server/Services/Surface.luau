-- Helpers for drawing on the front face of a part (registers' customer screens, boards).
-- Canvases are a fixed size in pixels worked out from the part, so layouts are predictable.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("POS")
local Palette = require(Shared.Palette)

local Surface = {}

local FAMILY = "rbxasset://fonts/families/BuilderSans.json"
Surface.Fonts = {
	Medium = Font.new(FAMILY, Enum.FontWeight.Medium),
	Bold = Font.new(FAMILY, Enum.FontWeight.Bold),
	Heavy = Font.new(FAMILY, Enum.FontWeight.ExtraBold),
	Mono = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold),
}

local PIXELS_PER_STUD = 100

-- Creates a SurfaceGui on the part's front face. Returns the gui, its root frame and its size.
function Surface.create(part: BasePart, name: string): (SurfaceGui, Frame, Vector2)
	local existing = part:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	local canvas = Vector2.new(part.Size.X, part.Size.Y) * PIXELS_PER_STUD
	local gui = Instance.new("SurfaceGui")
	gui.Name = name
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = canvas
	gui.LightInfluence = 0
	gui.Brightness = 1.4
	gui.MaxDistance = 120
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Adornee = part

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BorderSizePixel = 0
	root.BackgroundColor3 = Palette.Panel
	root.Parent = gui
	gui.Parent = part
	return gui, root, canvas
end

function Surface.new(className: string, props: { [string]: any }): any
	local instance = Instance.new(className)
	local parent
	for key, value in props do
		if key == "Parent" then
			parent = value
		else
			(instance :: any)[key] = value
		end
	end
	instance.Parent = parent
	return instance
end

function Surface.text(parent: Instance, props: { [string]: any }): TextLabel
	local defaults = {
		BackgroundTransparency = 1,
		TextColor3 = Palette.Text,
		FontFace = Surface.Fonts.Bold,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = parent,
	}
	for key, value in props do
		defaults[key] = value
	end
	return Surface.new("TextLabel", defaults)
end

function Surface.box(parent: Instance, props: { [string]: any }): Frame
	local defaults = { BorderSizePixel = 0, BackgroundColor3 = Palette.Raised, Parent = parent }
	local radius = props.Radius
	props.Radius = nil
	for key, value in props do
		defaults[key] = value
	end
	local frame = Surface.new("Frame", defaults)
	if radius then
		Surface.new("UICorner", { CornerRadius = UDim.new(0, radius), Parent = frame })
	end
	return frame
end

return Surface

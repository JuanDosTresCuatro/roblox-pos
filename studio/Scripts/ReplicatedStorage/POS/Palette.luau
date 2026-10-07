--!strict
-- Colours shared by the POS window, the kiosks and every screen in the world.
-- A clean white look with a warm yellow accent. Change these to rebrand everything at once.

local rgb = Color3.fromRGB

return {
	Backdrop = rgb(10, 10, 14),
	Bg = rgb(244, 244, 240),
	Panel = rgb(255, 255, 255),
	Raised = rgb(243, 243, 238),
	RaisedHover = rgb(232, 232, 225),
	Border = rgb(222, 222, 213),
	Text = rgb(23, 23, 26),
	Muted = rgb(102, 102, 110),
	Faint = rgb(150, 150, 158),

	Accent = rgb(255, 194, 14), -- brand yellow
	AccentHover = rgb(255, 207, 64),
	AccentSoft = rgb(255, 244, 205),
	AccentText = rgb(140, 90, 0), -- yellow is unreadable as text on white; use this instead
	OnAccent = rgb(23, 23, 26), -- text on a yellow fill

	Success = rgb(22, 163, 74),
	SuccessHover = rgb(30, 180, 86),
	SuccessSoft = rgb(220, 247, 228),
	OnSuccess = rgb(255, 255, 255),
	Warning = rgb(217, 119, 6),
	WarningSoft = rgb(254, 240, 199),
	Danger = rgb(220, 38, 38),
	DangerHover = rgb(235, 70, 70),
	DangerSoft = rgb(253, 226, 226),
	OnDanger = rgb(255, 255, 255),

	Paper = rgb(255, 255, 251),
	Ink = rgb(28, 28, 32),

	-- Physical equipment in the demo world
	Bezel = rgb(28, 30, 36),
	Steel = rgb(70, 74, 84),
	WhiteBody = rgb(236, 237, 240),
}

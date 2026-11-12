--!strict
-- Kartu gelap (CardDark) di kanan: Quick Info (Umur, Utang, Karir, Inventory).

local UIStyle = require(script.Parent.UIStyle)

export type InfoPanel = {
	Root: Frame,
	SetProfile: (self: InfoPanel, age: number, lifeStage: string, week: number) -> (),
	SetDebt: (self: InfoPanel, amount: number) -> (),
	SetCareer: (self: InfoPanel, career: string?) -> (),
	SetInventoryCount: (self: InfoPanel, count: number) -> (),
	_values: { [string]: TextLabel },
}

local InfoPanel = {}
InfoPanel.__index = InfoPanel

local ROW_HEIGHT = 56

local function CreateRow(icon: string, caption: string, order: number): (Frame, TextLabel)
	local colors = UIStyle.Colors

	local valueLabel = UIStyle.CreateLabel({
		Name = "Value",
		Text = "-",
		Font = UIStyle.Fonts.Bold,
		TextSize = 15,
		TextColor3 = colors.TextLight,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(52, 28),
		Size = UDim2.new(1, -62, 0, 18),
	})

	local row = UIStyle.CreateComponent("Frame", {
		Name = caption .. "Row",
		BackgroundColor3 = colors.RowDark,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -6, 0, ROW_HEIGHT),
		LayoutOrder = order,
		Corner = UIStyle.RadiusRow,
	}, {
		UIStyle.CreateLabel({
			Name = "Icon",
			Text = icon,
			TextSize = 22,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.fromOffset(32, ROW_HEIGHT),
		}),
		UIStyle.CreateLabel({
			Name = "Caption",
			Text = caption,
			TextSize = UIStyle.TextSize.Caption,
			TextColor3 = colors.Muted,
			Position = UDim2.fromOffset(52, 8),
			Size = UDim2.new(1, -62, 0, 16),
		}),
		valueLabel,
	})
	return row, valueLabel
end

function InfoPanel.new(parent: Instance?): InfoPanel
	local colors = UIStyle.Colors

	local list = UIStyle.CreateComponent("ScrollingFrame", {
		Name = "InfoList",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 1, -40),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = colors.Muted,
	}, {
		UIStyle.CreateComponent("UIListLayout", {
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})

	local values: { [string]: TextLabel } = {}
	local definitions = {
		{ Key = "Profile",   Icon = "🎂", Caption = "Umur" },
		{ Key = "Debt",      Icon = "💳", Caption = "Utang" },
		{ Key = "Career",    Icon = "💼", Caption = "Karir" },
		{ Key = "Inventory", Icon = "🎒", Caption = "Inventory" },
	}
	for index, def in ipairs(definitions) do
		local row, valueLabel = CreateRow(def.Icon, def.Caption, index)
		row.Parent = list
		values[def.Key] = valueLabel
	end

	local root = UIStyle.CreateComponent("Frame", {
		Name = "InfoPanel",
		BackgroundColor3 = colors.CardDark,
		BorderSizePixel = 0,
		Corner = true,
		Padding = UIStyle.Padding,
	}, {
		UIStyle.CreateLabel({
			Name = "Title",
			Text = "📌 Quick Info",
			Font = UIStyle.Fonts.Bold,
			TextSize = UIStyle.TextSize.Title,
			TextColor3 = colors.TextLight,
			Size = UDim2.new(1, 0, 0, 28),
		}),
		list,
	})
	if parent then
		root.Parent = parent
	end

	local self = setmetatable({ Root = root, _values = values }, InfoPanel)
	local panel = (self :: any) :: InfoPanel
	panel:SetDebt(0)
	panel:SetCareer(nil)
	panel:SetInventoryCount(0)
	return panel
end

function InfoPanel.SetProfile(self: InfoPanel, age: number, lifeStage: string, week: number)
	self._values.Profile.Text = ("%d th • %s • Mgg %d"):format(age, lifeStage, week)
end

function InfoPanel.SetDebt(self: InfoPanel, amount: number)
	local label = self._values.Debt
	label.Text = if amount > 0 then UIStyle.FormatRupiah(amount) else "Bebas utang"
	label.TextColor3 = if amount > 0 then UIStyle.Colors.Danger else UIStyle.Colors.StatCash
end

function InfoPanel.SetCareer(self: InfoPanel, career: string?)
	self._values.Career.Text = career or "Belum ada"
end

function InfoPanel.SetInventoryCount(self: InfoPanel, count: number)
	self._values.Inventory.Text = if count > 0 then ("%d item"):format(count) else "Kosong"
end

return InfoPanel
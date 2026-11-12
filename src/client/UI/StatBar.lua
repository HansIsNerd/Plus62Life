--!strict
-- Komponen Stat "Pill": latar abu gelap transparan, isi berwarna, teks (emoji + nilai) di tengah.

local TweenService = game:GetService("TweenService")
local UIStyle = require(script.Parent.UIStyle)

export type StatBarConfig = {
	Name: string,
	Icon: string,
	Color: Color3,
	Max: number,
	Format: ((value: number) -> string)?,
	Normalize: ((value: number) -> number)?, -- opsional: nilai -> 0..1 (untuk Cash yang tanpa batas atas)
	LayoutOrder: number?,
	Size: UDim2?,
	Parent: Instance?,
}

export type StatBar = {
	Root: Frame,
	Fill: Frame,
	ValueLabel: TextLabel,
	SetValue: (self: StatBar, value: number, animate: boolean?) -> (),
	SetFormat: (self: StatBar, format: (value: number) -> string) -> (),
	Destroy: (self: StatBar) -> (),
	_config: StatBarConfig,
	_format: (value: number) -> string,
	_value: number,
	_tween: Tween?,
}

local StatBar = {}
StatBar.__index = StatBar

local TWEEN_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PILL = UDim.new(0.5, 0) -- radius 50%

local function DefaultFormat(value: number): string
	return tostring(math.floor(value + 0.5))
end

function StatBar.new(config: StatBarConfig): StatBar
	local colors = UIStyle.Colors

	local fill = UIStyle.CreateComponent("Frame", {
		Name = "Fill",
		BackgroundColor3 = config.Color,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		ZIndex = 1,
		Corner = PILL,
	})

	local valueLabel = UIStyle.CreateLabel({
		Name = "Value",
		Text = "",
		Font = UIStyle.Fonts.Bold,
		TextScaled = true, -- otomatis mengecil di layar sempit
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
	}, {
		UIStyle.CreateComponent("UITextSizeConstraint", { MaxTextSize = 14, MinTextSize = 8 }),
		UIStyle.CreateComponent("UIPadding", {
			PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
			PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4),
		}),
	})

	local root = UIStyle.CreateComponent("Frame", {
		Name = config.Name .. "Pill",
		BackgroundColor3 = colors.BgDark,
		BackgroundTransparency = 0.85, -- abu-abu gelap transparan
		BorderSizePixel = 0,
		Size = config.Size or UDim2.new(0.25, -5, 1, 0),
		LayoutOrder = config.LayoutOrder or 0,
		Corner = PILL,
		Stroke = { Color = colors.TextDark, Thickness = 2 },
	}, { fill, valueLabel })

	if config.Parent then
		root.Parent = config.Parent
	end

	local self = setmetatable({
		Root = root,
		Fill = fill,
		ValueLabel = valueLabel,
		_config = config,
		_format = config.Format or DefaultFormat,
		_value = 0,
		_tween = nil,
	}, StatBar)

	local bar = (self :: any) :: StatBar
	bar:SetValue(0, false)
	return bar
end

function StatBar.SetValue(self: StatBar, value: number, animate: boolean?)
	self._value = value
	local config = self._config

	self.ValueLabel.Text = config.Icon .. " " .. self._format(value)
	-- Nilai negatif (saldo minus) -> teks merah
	self.ValueLabel.TextColor3 = if value < 0 then UIStyle.Colors.Danger else UIStyle.Colors.TextDark

	local fraction: number
	if config.Normalize then
		fraction = config.Normalize(value)
	else
		fraction = if config.Max > 0 then value / config.Max else 0
	end
	local target = UDim2.fromScale(math.clamp(fraction, 0, 1), 1) -- clamp 0..100%

	if self._tween then
		self._tween:Cancel()
		self._tween = nil
	end
	if animate == false then
		self.Fill.Size = target
		return
	end

	local tween = TweenService:Create(self.Fill, TWEEN_INFO, { Size = target })
	self._tween = tween
	tween:Play()
end

-- Ganti format teks (misal Cash penuh <-> ringkas) lalu render ulang tanpa animasi.
function StatBar.SetFormat(self: StatBar, format: (value: number) -> string)
	self._format = format
	self:SetValue(self._value, false)
end

function StatBar.Destroy(self: StatBar)
	if self._tween then
		self._tween:Cancel()
	end
	self.Root:Destroy()
end

return StatBar
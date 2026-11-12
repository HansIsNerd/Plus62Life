--!strict
-- src/client/UI/UIStyle.lua
-- Modern Soft UI / Bento Dashboard: gradient biru muda, card putih, radius 24, shadow tipis.

local UIStyle = {}

local function hex(value: string): Color3
	return Color3.fromHex(value)
end

UIStyle.Colors = {
	-- Latar
	BgTop          = hex("C6E2F5"),
	BgBottom       = hex("E8F4F8"),
	Card           = hex("FFFFFF"),
	Row            = hex("F5F8FB"), -- latar baris kecil di dalam card
	Track          = hex("E5EDF3"), -- latar progress bar
	Shadow         = hex("000000"),
	-- Teks
	TextDark       = hex("1A1A1A"),
	TextLight      = hex("FFFFFF"),
	TextMuted      = hex("8E99A4"),
	TextMoney      = hex("1F9D43"), -- hijau teks yang terbaca di latar terang
	-- Aksen
	Primary        = hex("34C759"),
	Danger         = hex("FF3B30"),
	Info           = hex("007AFF"),
	Warning        = hex("FF9500"),
	-- Stat
	StatCash       = hex("34C759"),
	StatHealth     = hex("FF5A5F"),
	StatStress     = hex("FFC83D"),
	StatReputation = hex("4DA6FF"),
	-- Tombol
	ButtonBlack    = hex("111111"),
	ButtonDisabled = hex("6B6B70"),
}

UIStyle.Fonts = {
	Regular = Enum.Font.Gotham,
	Medium  = Enum.Font.GothamMedium,
	Bold    = Enum.Font.GothamBold,
}

UIStyle.TextSize = { Title = 20, Body = 14, Caption = 12, Button = 20 }
UIStyle.Radius        = 24 -- card
UIStyle.RadiusSmall   = 16 -- baris di dalam card
UIStyle.Padding       = 32 -- padding layar
UIStyle.CardPadding   = 24 -- padding di dalam card
UIStyle.Gap           = 24 -- jarak antar card
UIStyle.COMPACT_WIDTH = 700 -- di bawah ini kolom ditumpuk vertikal (HP)

export type Props = { [string]: any }

--[[
	Membuat instance UI sekaligus.
	Key khusus di `properties`:
	  Corner   = true | number | UDim         -> UICorner (true = radius 24)
	  Padding  = number                       -> UIPadding 4 sisi
	  Stroke   = true | { Color, Thickness }  -> UIStroke
	  Gradient = { From, To, Rotation }       -> UIGradient
	  Parent   = Instance                     -> di-set TERAKHIR (performa)
]]
function UIStyle.CreateComponent(className: string, properties: Props?, children: { Instance }?): any
	local instance: any = Instance.new(className)
	local parent: Instance? = nil
	local corner: any = nil
	local padding: number? = nil
	local stroke: any = nil
	local gradient: any = nil

	if properties then
		for key, value in pairs(properties) do
			if key == "Parent" then
				parent = value
			elseif key == "Corner" then
				corner = value
			elseif key == "Padding" and typeof(value) == "number" then
				-- Angka = UIPadding 4 sisi. UDim (misal Padding UIListLayout) diteruskan apa adanya.
				padding = value
			elseif key == "Stroke" then
				stroke = value
			elseif key == "Gradient" then
				gradient = value
			else
				instance[key] = value
			end
		end
	end

	if corner then
		local uiCorner = Instance.new("UICorner")
		if typeof(corner) == "UDim" then
			uiCorner.CornerRadius = corner
		elseif typeof(corner) == "number" then
			uiCorner.CornerRadius = UDim.new(0, corner)
		else
			uiCorner.CornerRadius = UDim.new(0, UIStyle.Radius)
		end
		uiCorner.Parent = instance
	end

	if padding then
		local uiPadding = Instance.new("UIPadding")
		local p = UDim.new(0, padding)
		uiPadding.PaddingTop, uiPadding.PaddingBottom = p, p
		uiPadding.PaddingLeft, uiPadding.PaddingRight = p, p
		uiPadding.Parent = instance
	end

	if stroke then
		local uiStroke = Instance.new("UIStroke")
		local color = UIStyle.Colors.Track
		local thickness = 1
		if typeof(stroke) == "table" then
			color = stroke.Color or color
			thickness = stroke.Thickness or thickness
		end
		uiStroke.Color = color
		uiStroke.Thickness = thickness
		uiStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		uiStroke.Parent = instance
	end

	if gradient then
		local uiGradient = Instance.new("UIGradient")
		uiGradient.Color = ColorSequence.new(gradient.From, gradient.To)
		uiGradient.Rotation = gradient.Rotation or 0
		uiGradient.Parent = instance
	end

	if children then
		for _, child in ipairs(children) do
			child.Parent = instance
		end
	end

	if parent then
		instance.Parent = parent
	end
	return instance
end

-- TextLabel dengan default (Gotham, TextDark, rata kiri). Properti di `properties` menimpa default.
function UIStyle.CreateLabel(properties: Props, children: { Instance }?): any
	local merged: Props = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = UIStyle.Fonts.Regular,
		TextSize = UIStyle.TextSize.Body,
		TextColor3 = UIStyle.Colors.TextDark,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for key, value in pairs(properties) do
		merged[key] = value
	end
	return UIStyle.CreateComponent("TextLabel", merged, children)
end

-- ScrollingFrame vertikal dengan canvas otomatis. Tambahkan UIListLayout sendiri lewat `children`.
function UIStyle.CreateScroll(properties: Props?, children: { Instance }?): any
	local merged: Props = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = UIStyle.Colors.TextMuted,
		Size = UDim2.fromScale(1, 1),
	}
	if properties then
		for key, value in pairs(properties) do
			merged[key] = value
		end
	end
	return UIStyle.CreateComponent("ScrollingFrame", merged, children)
end

--[[
	Card putih radius 24 dengan shadow tipis.
	Roblox tidak punya shadow bawaan, jadi dibuat dari wrapper transparan berisi
	[Shadow (digeser 4px ke bawah), Card]. Wrapper yang ikut diatur oleh UIListLayout.
	Mengembalikan (wrapper, card): isi konten ke `card`, atur Size/LayoutOrder lewat properties.
]]
function UIStyle.CreateCard(properties: Props?, children: { Instance }?): (any, any)
	local props: Props = properties or {}
	local name: string = props.Name or "Card"

	local shadow = UIStyle.CreateComponent("Frame", {
		Name = "Shadow",
		BackgroundColor3 = UIStyle.Colors.Shadow,
		BackgroundTransparency = 0.92,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 4),
		Size = UDim2.fromScale(1, 1),
		Corner = true,
	})

	local card = UIStyle.CreateComponent("Frame", {
		Name = name,
		BackgroundColor3 = UIStyle.Colors.Card,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Corner = true,
		Padding = UIStyle.CardPadding,
	}, children)

	local wrapper = UIStyle.CreateComponent("Frame", {
		Name = name .. "Wrapper",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = props.Size or UDim2.fromScale(1, 1),
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	}, { shadow, card })

	return wrapper, card
end

-- Uang = hijau, Bahaya = merah, Event = oranye, lainnya (Info) = hitam.
function UIStyle.GetLogColor(logType: string?): Color3
	if logType == "Uang" or logType == "Success" then
		return UIStyle.Colors.TextMoney
	elseif logType == "Bahaya" then
		return UIStyle.Colors.Danger
	elseif logType == "Event" then
		return UIStyle.Colors.Warning
	end
	return UIStyle.Colors.TextDark
end

-- 1500000 -> "Rp 1.500.000", -300 -> "-Rp 300"
function UIStyle.FormatRupiah(amount: number): string
	local sign = if amount < 0 then "-" else ""
	local digits = string.format("%.0f", math.abs(amount))
	local withDots = string.gsub(string.reverse(digits), "(%d%d%d)", "%1.")
	local result = string.reverse(withDots)
	if string.sub(result, 1, 1) == "." then
		result = string.sub(result, 2)
	end
	return sign .. "Rp " .. result
end

return UIStyle
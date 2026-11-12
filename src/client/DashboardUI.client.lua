--!nonstrict
-- src/client/DashboardUI.client.lua
-- Layout 3 kolom: Kiri (Profil + Stat) 25% | Tengah (Timeline) 45% | Kanan (Quick Info + NEXT WEEK) 30%.
-- StatBar.lua, LogPanel.lua, dan InfoPanel.lua versi lama sudah tidak dipakai; boleh dihapus.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService        = game:GetService("GuiService")
local TweenService      = game:GetService("TweenService")

local Network   = require(ReplicatedStorage.Shared.Network)
local Config    = require(ReplicatedStorage.Shared.Config)
local GameState = require(ReplicatedStorage.Shared.GameState)
local UIStyle   = require(script.Parent:WaitForChild("UI"):WaitForChild("UIStyle"))

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Colors    = UIStyle.Colors
local Fonts     = UIStyle.Fonts

-- ===== Konstanta =====
local GAP              = UIStyle.Gap
local BUTTON_HEIGHT    = 64
local TOPBAR_FALLBACK  = 58 -- tinggi topbar bawaan Roblox (logo, menu, chat, mic)
local MAX_LOG_ROWS     = 100
local BOTTOM_THRESHOLD = 24 -- px; dianggap "di bawah" kalau selisih <= ini
local NEXT_TEXT        = "NEXT WEEK ▶"
local PILL             = UDim.new(0.5, 0)
local FILL_TWEEN       = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HOVER_TWEEN      = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local camera = workspace.CurrentCamera
while not camera do
	task.wait()
	camera = workspace.CurrentCamera
end

-- Area atas yang dipakai tombol bawaan Roblox (IgnoreGuiInset = true membuat UI kita menimpanya).
local function GetTopInset(): number
	local inset = GuiService:GetGuiInset().Y
	local ok, topbarBottom = pcall(function()
		return GuiService.TopbarInset.Max.Y
	end)
	local value = math.max(inset, if ok then topbarBottom else 0)
	if value < 36 then
		value = TOPBAR_FALLBACK
	end
	return value
end

-- ===== ScreenGui + Background gradient =====
local screenGui = UIStyle.CreateComponent("ScreenGui", {
	Name = "DashboardUI",
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 10,
})

UIStyle.CreateComponent("Frame", {
	Name = "Background",
	BackgroundColor3 = Colors.BgTop,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 0,
	Gradient = { From = Colors.BgTop, To = Colors.BgBottom, Rotation = 90 },
	Parent = screenGui,
})

-- ===== Root: 3 kolom horizontal =====
local rootPadding = UIStyle.CreateComponent("UIPadding", {})
local rootLayout = UIStyle.CreateComponent("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, GAP),
	SortOrder = Enum.SortOrder.LayoutOrder,
})

local root = UIStyle.CreateComponent("Frame", {
	Name = "Root",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1, 1),
	Parent = screenGui,
}, { rootPadding, rootLayout })

-- ===== KOLOM KIRI: Profil + 4 Stat Bar =====
local leftWrapper, leftCard = UIStyle.CreateCard({
	Name = "StatsCard",
	Size = UDim2.new(0.25, -16, 1, 0),
	LayoutOrder = 1,
	Parent = root,
})

local leftScroll = UIStyle.CreateScroll({ Name = "StatsScroll", Parent = leftCard }, {
	UIStyle.CreateComponent("UIListLayout", {
		Padding = UDim.new(0, 16),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

-- Profil: avatar + nama + umur
local avatarImage = UIStyle.CreateComponent("ImageLabel", {
	Name = "Avatar",
	BackgroundColor3 = Colors.Row,
	BorderSizePixel = 0,
	Size = UDim2.fromOffset(72, 72),
	Corner = PILL,
})
local nameLabel = UIStyle.CreateLabel({
	Name = "PlayerName",
	Text = player.DisplayName,
	Font = Fonts.Bold,
	TextSize = UIStyle.TextSize.Title,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Position = UDim2.fromOffset(84, 10),
	Size = UDim2.new(1, -92, 0, 28),
})
local ageLabel = UIStyle.CreateLabel({
	Name = "PlayerAge",
	Text = "Umur 0",
	TextSize = UIStyle.TextSize.Caption,
	TextColor3 = Colors.TextMuted,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Position = UDim2.fromOffset(84, 40),
	Size = UDim2.new(1, -92, 0, 20),
})
UIStyle.CreateComponent("Frame", {
	Name = "Profile",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Size = UDim2.new(1, -8, 0, 72),
	LayoutOrder = 1,
	Parent = leftScroll,
}, { avatarImage, nameLabel, ageLabel })

task.spawn(function()
	local ok, content = pcall(function()
		return Players:GetUserThumbnailAsync(
			player.UserId,
			Enum.ThumbnailType.HeadShot,
			Enum.ThumbnailSize.Size150x150
		)
	end)
	if ok and content then
		avatarImage.Image = content
	end
end)

-- Stat bar vertikal: [icon + nama ........ nilai] + progress pill di bawahnya
local function CreateStatRow(def, order)
	local fill = UIStyle.CreateComponent("Frame", {
		Name = "Fill",
		BackgroundColor3 = def.Color,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Corner = PILL,
	})
	local track = UIStyle.CreateComponent("Frame", {
		Name = "Track",
		BackgroundColor3 = Colors.Track,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 0, 10),
		Corner = PILL,
	}, { fill })
	local titleLabel = UIStyle.CreateLabel({
		Name = "Title",
		Text = def.Icon .. "  " .. def.Label,
		Font = Fonts.Bold,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(0.5, 0, 0, 24),
	})
	local valueLabel = UIStyle.CreateLabel({
		Name = "Value",
		Text = "",
		Font = Fonts.Bold,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.new(0.5, 0, 0, 24),
	})
	UIStyle.CreateComponent("Frame", {
		Name = def.Key .. "Row",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -8, 0, 46),
		LayoutOrder = order,
		Parent = leftScroll,
	}, { titleLabel, valueLabel, track })

	local currentTween = nil
	local function SetValue(value: number, animate: boolean?)
		valueLabel.Text = def.Format(value)
		valueLabel.TextColor3 = if value < 0 then Colors.Danger else Colors.TextDark

		local fraction = if def.Normalize then def.Normalize(value) else value / def.Max
		local target = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)

		if currentTween then
			currentTween:Cancel()
			currentTween = nil
		end
		if animate == false then
			fill.Size = target
			return
		end
		currentTween = TweenService:Create(fill, FILL_TWEEN, { Size = target })
		currentTween:Play()
	end

	SetValue(0, false)
	return SetValue
end

local function FormatOutOf(max: number)
	return function(value: number): string
		return ("%d/%d"):format(math.floor(value + 0.5), max)
	end
end

-- Cash tidak punya batas atas -> skala logaritmik (Rp 1 miliar = penuh).
local function NormalizeCash(value: number): number
	if value <= 0 then
		return 0
	end
	return math.log10(value + 1) / 9
end

local statSetters = {
	Cash = CreateStatRow({
		Key = "Cash", Label = "Uang", Icon = "💵", Color = Colors.StatCash,
		Max = 1, Format = UIStyle.FormatRupiah, Normalize = NormalizeCash,
	}, 2),
	Health = CreateStatRow({
		Key = "Health", Label = "Kesehatan", Icon = "❤️", Color = Colors.StatHealth,
		Max = Config.Stats.Health.Max, Format = FormatOutOf(Config.Stats.Health.Max),
	}, 3),
	Stress = CreateStatRow({
		Key = "Stress", Label = "Stres", Icon = "😫", Color = Colors.StatStress,
		Max = Config.Stats.Stress.Max, Format = FormatOutOf(Config.Stats.Stress.Max),
	}, 4),
	Reputation = CreateStatRow({
		Key = "Reputation", Label = "Reputasi", Icon = "⭐", Color = Colors.StatReputation,
		Max = Config.Stats.Reputation.Max, Format = FormatOutOf(Config.Stats.Reputation.Max),
	}, 5),
}

-- ===== KOLOM TENGAH: Timeline Kejadian =====
local midWrapper, midCard = UIStyle.CreateCard({
	Name = "TimelineCard",
	Size = UDim2.new(0.45, -16, 1, 0),
	LayoutOrder = 2,
	Parent = root,
})

UIStyle.CreateLabel({
	Name = "Title",
	Text = "📜 Timeline Kejadian",
	Font = Fonts.Bold,
	TextSize = UIStyle.TextSize.Title,
	Size = UDim2.new(1, 0, 0, 28),
	Parent = midCard,
})

local logScroll = UIStyle.CreateScroll({
	Name = "LogScroll",
	Position = UDim2.fromOffset(0, 44),
	Size = UDim2.new(1, 0, 1, -44),
	Parent = midCard,
}, {
	UIStyle.CreateComponent("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

local logRows = {}        -- { Frame = Frame, Key = string? } terurut dari terlama
local logSeen = {}        -- [key] = true, untuk dedupe riwayat vs event
local logOrder = 0
local logAutoScroll = true

local function MaxCanvasY(): number
	return math.max(0, logScroll.AbsoluteCanvasSize.Y - logScroll.AbsoluteWindowSize.Y)
end

-- Canvas membesar -> tetap di bawah selama user tidak scroll ke atas.
logScroll:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(function()
	if logAutoScroll then
		logScroll.CanvasPosition = Vector2.new(0, MaxCanvasY())
	end
end)
-- Scroll manual menjauhi bawah -> matikan auto-scroll.
logScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
	logAutoScroll = (MaxCanvasY() - logScroll.CanvasPosition.Y) <= BOTTOM_THRESHOLD
end)

local function AddLogEntry(entry)
	-- Dedupe: riwayat dari GetData bisa tumpang tindih dengan event LogAdded yang datang lebih dulu.
	local key = nil
	if entry.Time then
		key = ("%d|%s|%s"):format(entry.Time, tostring(entry.Week), tostring(entry.Text))
		if logSeen[key] then
			return
		end
		logSeen[key] = true
	end

	logOrder += 1
	local row = UIStyle.CreateComponent("Frame", {
		Name = "LogRow",
		BackgroundColor3 = Colors.Row,
		BorderSizePixel = 0,
		AutomaticSize = Enum.AutomaticSize.Y, -- minimum 48px, melebar kalau teks lebih dari 1 baris
		Size = UDim2.new(1, -8, 0, 48),
		LayoutOrder = logOrder,
		Corner = UIStyle.RadiusSmall,
	}, {
		UIStyle.CreateLabel({
			Name = "Icon",
			Text = entry.Icon or "📝",
			TextSize = 20,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(8, 0),
			Size = UDim2.fromOffset(32, 48),
		}),
		UIStyle.CreateLabel({
			Name = "Text",
			Text = tostring(entry.Text),
			Font = Fonts.Bold,
			TextSize = 13,
			TextColor3 = UIStyle.GetLogColor(entry.Type),
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Center,
			AutomaticSize = Enum.AutomaticSize.Y,
			Position = UDim2.fromOffset(48, 0),
			Size = UDim2.new(1, -60, 0, 48),
		}, {
			UIStyle.CreateComponent("UIPadding", {
				PaddingTop = UDim.new(0, 8),
				PaddingBottom = UDim.new(0, 8),
			}),
		}),
	})
	row.Parent = logScroll

	table.insert(logRows, { Frame = row, Key = key })
	while #logRows > MAX_LOG_ROWS do
		local oldest = table.remove(logRows, 1)
		if oldest then
			oldest.Frame:Destroy()
			if oldest.Key then
				logSeen[oldest.Key] = nil
			end
		end
	end
end

-- ===== KOLOM KANAN: Quick Info (atas) + NEXT WEEK (bawah) =====
local rightColumn = UIStyle.CreateComponent("Frame", {
	Name = "RightColumn",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Size = UDim2.new(0.30, -16, 1, 0),
	LayoutOrder = 3,
	Parent = root,
}, {
	UIStyle.CreateComponent("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		Padding = UDim.new(0, GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

local infoWrapper, infoCard = UIStyle.CreateCard({
	Name = "QuickInfoCard",
	Size = UDim2.new(1, 0, 1, -(BUTTON_HEIGHT + GAP)),
	LayoutOrder = 1,
	Parent = rightColumn,
})

UIStyle.CreateLabel({
	Name = "Title",
	Text = "📌 Quick Info",
	Font = Fonts.Bold,
	TextSize = UIStyle.TextSize.Title,
	Size = UDim2.new(1, 0, 0, 28),
	Parent = infoCard,
})

local infoScroll = UIStyle.CreateScroll({
	Name = "InfoScroll",
	Position = UDim2.fromOffset(0, 44),
	Size = UDim2.new(1, 0, 1, -44),
	Parent = infoCard,
}, {
	UIStyle.CreateComponent("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

local INFO_ROW_HEIGHT = 56

local function CreateInfoRow(icon: string, caption: string, order: number)
	local valueLabel = UIStyle.CreateLabel({
		Name = "Value",
		Text = "-",
		Font = Fonts.Bold,
		TextSize = 15,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(52, 28),
		Size = UDim2.new(1, -62, 0, 18),
	})
	UIStyle.CreateComponent("Frame", {
		Name = caption .. "Row",
		BackgroundColor3 = Colors.Row,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -8, 0, INFO_ROW_HEIGHT),
		LayoutOrder = order,
		Corner = UIStyle.RadiusSmall,
		Parent = infoScroll,
	}, {
		UIStyle.CreateLabel({
			Name = "Icon",
			Text = icon,
			TextSize = 22,
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.fromOffset(32, INFO_ROW_HEIGHT),
		}),
		UIStyle.CreateLabel({
			Name = "Caption",
			Text = caption,
			TextSize = UIStyle.TextSize.Caption,
			TextColor3 = Colors.TextMuted,
			Position = UDim2.fromOffset(52, 8),
			Size = UDim2.new(1, -62, 0, 16),
		}),
		valueLabel,
	})
	return valueLabel
end

local stageValue     = CreateInfoRow("🎂", "Tahap Hidup", 1)
local debtValue      = CreateInfoRow("💳", "Utang", 2)
local careerValue    = CreateInfoRow("💼", "Karir", 3)
local inventoryValue = CreateInfoRow("🎒", "Inventory", 4)

local function SetDebt(amount: number)
	debtValue.Text = if amount > 0 then UIStyle.FormatRupiah(amount) else "Bebas utang"
	debtValue.TextColor3 = if amount > 0 then Colors.Danger else Colors.TextMoney
end

-- Tombol NEXT WEEK: pill hitam, hover biru
local nextButton = UIStyle.CreateComponent("TextButton", {
	Name = "NextWeekButton",
	Text = NEXT_TEXT,
	Font = Fonts.Bold,
	TextSize = UIStyle.TextSize.Button,
	TextColor3 = Colors.TextLight,
	BackgroundColor3 = Colors.ButtonBlack,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Size = UDim2.new(1, 0, 0, BUTTON_HEIGHT),
	LayoutOrder = 2,
	Corner = PILL,
	Parent = rightColumn,
})

local serverBusy = false -- dari GameStateChanged
local localBusy = false  -- selama InvokeServer berjalan
local hovering = false

local function UpdateNextButton()
	local busy = serverBusy or localBusy
	nextButton.Active = not busy
	nextButton.Text = if busy then "WAIT..." else NEXT_TEXT

	local target = Colors.ButtonBlack
	if busy then
		target = Colors.ButtonDisabled
	elseif hovering then
		target = Colors.Info
	end
	TweenService:Create(nextButton, HOVER_TWEEN, { BackgroundColor3 = target }):Play()
end

nextButton.MouseEnter:Connect(function()
	hovering = true
	UpdateNextButton()
end)
nextButton.MouseLeave:Connect(function()
	hovering = false
	UpdateNextButton()
end)

-- ===== Responsive layout =====
local function Relayout()
	local viewport = camera.ViewportSize
	local compact = viewport.X < UIStyle.COMPACT_WIDTH
	local pad = if compact then 16 else UIStyle.Padding

	rootPadding.PaddingLeft = UDim.new(0, pad)
	rootPadding.PaddingRight = UDim.new(0, pad)
	rootPadding.PaddingBottom = UDim.new(0, pad)
	-- Atas: minimal `pad`, tapi tidak boleh tertimpa tombol bawaan Roblox (logo, menu, chat).
	rootPadding.PaddingTop = UDim.new(0, math.max(pad, GetTopInset() + 8))

	if compact then
		-- HP portrait: tiga card ditumpuk vertikal (total tinggi = 100% - 3x16 + 2x24 gap = pas)
		rootLayout.FillDirection = Enum.FillDirection.Vertical
		leftWrapper.Size = UDim2.new(1, 0, 0.30, -16)
		midWrapper.Size = UDim2.new(1, 0, 0.36, -16)
		rightColumn.Size = UDim2.new(1, 0, 0.34, -16)
	else
		-- Desktop: 25% / 45% / 30% (masing-masing dikurangi 16px: 3 x 16 = 2 gap x 24)
		rootLayout.FillDirection = Enum.FillDirection.Horizontal
		leftWrapper.Size = UDim2.new(0.25, -16, 1, 0)
		midWrapper.Size = UDim2.new(0.45, -16, 1, 0)
		rightColumn.Size = UDim2.new(0.30, -16, 1, 0)
	end
end

camera:GetPropertyChangedSignal("ViewportSize"):Connect(Relayout)
pcall(function()
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(Relayout)
end)
Relayout()

-- ===== Data dari server =====
local function ApplyProfile(data)
	ageLabel.Text = ("Umur %d • Minggu %d"):format(data.Age, data.Week)
	stageValue.Text = tostring(data.LifeStage)
	SetDebt(data.Stats.Debt or 0)
	careerValue.Text = if type(data.Career) == "string" then data.Career else "Belum ada"
	local itemCount = if type(data.Inventory) == "table" then #data.Inventory else 0
	inventoryValue.Text = if itemCount > 0 then ("%d item"):format(itemCount) else "Kosong"
end

local function RefreshProfile()
	local ok, data = pcall(function()
		return Network:InvokeServer("GetData")
	end)
	if ok and data then
		ApplyProfile(data)
	else
		warn("[DashboardUI] Gagal refresh profil:", data)
	end
end

-- Listener dipasang SEBELUM GetData supaya tidak ada event yang terlewat.
Network:OnClientEvent("StatChanged", function(statName, newValue)
	local setter = statSetters[statName]
	if setter then
		setter(newValue, true)
	end
	if statName == "Debt" then
		SetDebt(newValue)
	end
end)

Network:OnClientEvent("LogAdded", function(entry)
	AddLogEntry(entry)
end)

Network:OnClientEvent("GameStateChanged", function(state)
	serverBusy = (state ~= GameState.State.IDLE)
	UpdateNextButton()
end)

nextButton.Activated:Connect(function()
	if serverBusy or localBusy then
		return
	end
	localBusy = true
	UpdateNextButton()

	local ok, success, message = pcall(function()
		return Network:InvokeServer("NextWeek")
	end)
	if not ok then
		warn("[DashboardUI] NextWeek error:", success)
		AddLogEntry({ Text = "Koneksi ke server bermasalah, coba lagi.", Type = "Bahaya", Icon = "⚠️" })
	elseif success == false then
		AddLogEntry({ Text = message or "Tidak bisa lanjut minggu sekarang.", Type = "Bahaya", Icon = "⚠️" })
	end

	-- Server belum mengirim event umur -> sinkronkan via GetData setelah minggu selesai.
	RefreshProfile()

	localBusy = false
	UpdateNextButton()
end)

-- Muat data awal
task.spawn(function()
	local ok, data = pcall(function()
		return Network:InvokeServer("GetData")
	end)
	if not ok or not data then
		warn("[DashboardUI] Gagal memuat data awal:", data)
		AddLogEntry({ Text = "Gagal memuat data. Coba rejoin.", Type = "Bahaya", Icon = "⚠️" })
		return
	end

	for statName, setter in pairs(statSetters) do
		setter(data.Stats[statName] or 0, false)
	end
	ApplyProfile(data)
	for _, entry in ipairs(data.Log) do
		AddLogEntry(entry)
	end
end)

UpdateNextButton()
screenGui.Parent = playerGui
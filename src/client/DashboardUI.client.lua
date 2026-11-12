--!nonstrict
-- src/client/DashboardUI.client.lua
-- Layout 3 kolom: Kiri (Profil + Stat) 25% | Tengah (Timeline) 45% | Kanan (Quick Info + NEXT WEEK + Kerja) 30%.
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
local GAP                = UIStyle.Gap
local RIGHT_GAP          = 12 -- jarak antar elemen di kolom kanan (lebih rapat agar muat 2 tombol)
local BUTTON_HEIGHT      = 64
local WORK_BUTTON_HEIGHT = 56
local TOPBAR_FALLBACK    = 58 -- tinggi topbar bawaan Roblox (logo, menu, chat, mic)
local MAX_LOG_ROWS       = 100
local BOTTOM_THRESHOLD   = 24 -- px; dianggap "di bawah" kalau selisih <= ini
local NEXT_TEXT          = "NEXT WEEK ▶"
local WORK_TEXT          = "Kerja: Narik Ojol 🛵"
local PILL               = UDim.new(0.5, 0)
local FILL_TWEEN         = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HOVER_TWEEN        = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- Anti-stuck & loading
local NEXT_WEEK_TIMEOUT   = 15 -- detik; batas tunggu InvokeServer("NextWeek")
local GETDATA_TIMEOUT     = 6  -- detik; batas tunggu InvokeServer("GetData")
local WATCHDOG_NEXT_WEEK  = 25 -- detik; paksa reset tombol jika masih busy
local WATCHDOG_MINIGAME   = 45 -- detik; mini-game 15 detik + hasil + toleransi
local LOAD_ATTEMPTS       = 6  -- percobaan GetData saat server masih memuat
local LOAD_RETRY_DELAY    = 2  -- detik antar percobaan

local camera = workspace.CurrentCamera
while not camera do
	task.wait()
	camera = workspace.CurrentCamera
end

-- Bridge ke OjolRunner.client.lua (LocalScript tidak bisa di-require, jadi pakai BindableEvent lokal)
local function GetBindable(name: string): BindableEvent
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing and existing:IsA("BindableEvent") then
		return existing
	end
	local event = Instance.new("BindableEvent")
	event.Name = name
	event.Parent = ReplicatedStorage
	return event
end

local miniGameOpen   = GetBindable("MiniGameOpen")
local miniGameClosed = GetBindable("MiniGameClosed")

-- InvokeServer yang tidak pernah menggantung: pcall + timeout.
-- Mengembalikan (false, pesanError) jika error/timeout, atau (true, ...hasil server).
local function SafeInvoke(timeout: number, remoteName: string, ...)
	local args = table.pack(...)
	local done = false
	local results = nil

	task.spawn(function()
		results = table.pack(pcall(function()
			return Network:InvokeServer(remoteName, table.unpack(args, 1, args.n))
		end))
		done = true
	end)

	local startClock = os.clock()
	while not done and (os.clock() - startClock) < timeout do
		task.wait(0.05)
	end
	if not done or not results then
		return false, "timeout"
	end
	return table.unpack(results, 1, results.n)
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

-- Referensi komponen UI untuk update data. nil sampai semua komponen selesai dibangun.
local ui = nil

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
		if type(value) ~= "number" or value ~= value then
			value = 0 -- nil / NaN -> aman
		end
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
	if type(entry) ~= "table" then
		return
	end

	-- Dedupe: riwayat dari GetData bisa tumpang tindih dengan event LogAdded yang datang lebih dulu.
	local key = nil
	if entry.Time then
		key = ("%s|%s|%s"):format(tostring(entry.Time), tostring(entry.Week), tostring(entry.Text))
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
			Text = tostring(entry.Icon or "📝"),
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

-- ===== KOLOM KANAN: Quick Info (atas) + NEXT WEEK + Kerja (bawah) =====
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
		Padding = UDim.new(0, RIGHT_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

local infoWrapper, infoCard = UIStyle.CreateCard({
	Name = "QuickInfoCard",
	-- sisa tinggi = 100% - (tombol Next + tombol Kerja + 2 gap)
	Size = UDim2.new(1, 0, 1, -(BUTTON_HEIGHT + WORK_BUTTON_HEIGHT + RIGHT_GAP * 2)),
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
	if type(amount) ~= "number" or amount ~= amount then
		amount = 0
	end
	debtValue.Text = if amount > 0 then UIStyle.FormatRupiah(amount) else "Bebas utang"
	debtValue.TextColor3 = if amount > 0 then Colors.Danger else Colors.TextMoney
end

-- Tombol NEXT WEEK: pill hitam, hover biru
local nextBtn = UIStyle.CreateComponent("TextButton", {
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

-- Tombol Kerja: pill hijau (teks gelap agar kontras), abu saat sibuk
local workBtn = UIStyle.CreateComponent("TextButton", {
	Name = "WorkOjolButton",
	Text = WORK_TEXT,
	Font = Fonts.Bold,
	TextSize = 16,
	TextColor3 = Colors.TextDark,
	BackgroundColor3 = Colors.Primary,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Size = UDim2.new(1, 0, 0, WORK_BUTTON_HEIGHT),
	LayoutOrder = 3,
	Corner = PILL,
	Parent = rightColumn,
})

local serverBusy = false -- dari GameStateChanged
local localBusy = false  -- selama invoke / mini-game berjalan
local hovering = false
local workHovering = false
local busyToken = 0      -- penanda watchdog; naik setiap Arm/Reset sehingga watchdog lama batal

local function UpdateButtons()
	local busy = serverBusy or localBusy

	-- Next Week
	nextBtn.Active = not busy
	nextBtn.Text = if busy then "WAIT..." else NEXT_TEXT
	local nextTarget = Colors.ButtonBlack
	if busy then
		nextTarget = Colors.ButtonDisabled
	elseif hovering then
		nextTarget = Colors.Info
	end
	TweenService:Create(nextBtn, HOVER_TWEEN, { BackgroundColor3 = nextTarget }):Play()

	-- Kerja
	workBtn.Active = not busy
	local workColor = Colors.Primary
	local workText = Colors.TextDark
	if busy then
		workColor = Colors.ButtonDisabled
		workText = Colors.TextLight
	elseif workHovering then
		workColor = Colors.Info
		workText = Colors.TextLight
	end
	TweenService:Create(workBtn, HOVER_TWEEN, { BackgroundColor3 = workColor, TextColor3 = workText }):Play()
end

-- Reset paksa: tombol SELALU kembali normal (dipanggil setelah invoke selesai, sukses maupun gagal).
local function ResetButtons()
	busyToken += 1
	localBusy = false
	serverBusy = false
	nextBtn.Text = NEXT_TEXT
	nextBtn.Active = true
	workBtn.Active = true
	UpdateButtons()
end

-- Watchdog: jika masih busy setelah `seconds` dan tidak ada Arm/Reset baru, paksa reset.
local function ArmWatchdog(seconds: number)
	busyToken += 1
	local token = busyToken
	task.delay(seconds, function()
		if token == busyToken and (localBusy or serverBusy) then
			warn("[DashboardUI] Watchdog: tombol macet, direset paksa.")
			ResetButtons()
		end
	end)
end

nextBtn.MouseEnter:Connect(function()
	hovering = true
	UpdateButtons()
end)
nextBtn.MouseLeave:Connect(function()
	hovering = false
	UpdateButtons()
end)
workBtn.MouseEnter:Connect(function()
	workHovering = true
	UpdateButtons()
end)
workBtn.MouseLeave:Connect(function()
	workHovering = false
	UpdateButtons()
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
		-- HP portrait: tiga card ditumpuk vertikal
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

-- Semua komponen sudah ada -> `ui` siap dipakai.
ui = { StatSetters = statSetters }

-- ===== Data dari server (semua tahan nil / data tidak lengkap) =====
local function ApplyProfile(data)
	if not ui or type(data) ~= "table" then
		return
	end
	local stats = if type(data.Stats) == "table" then data.Stats else {}
	local age = math.floor(tonumber(data.Age) or 0)
	local week = math.floor(tonumber(data.Week) or 0)

	ageLabel.Text = ("Umur %d • Minggu %d"):format(age, week)
	stageValue.Text = tostring(data.LifeStage or "-")
	SetDebt(tonumber(stats.Debt) or 0)
	careerValue.Text = if type(data.Career) == "string" then data.Career else "Belum ada"
	local itemCount = if type(data.Inventory) == "table" then #data.Inventory else 0
	inventoryValue.Text = if itemCount > 0 then ("%d item"):format(itemCount) else "Kosong"
end

-- Fallback: ui nil / data nil / Stats tidak lengkap -> berhenti tanpa crash.
local function UpdateStatUI(data)
	if not ui then
		return
	end
	if type(data) ~= "table" or type(data.Stats) ~= "table" then
		return
	end
	for statName, setter in pairs(ui.StatSetters) do
		local value = data.Stats[statName]
		if type(value) ~= "number" then
			value = 0
		end
		setter(value, false)
	end
	ApplyProfile(data)
end

local function AddHistory(data)
	if type(data) ~= "table" or type(data.Log) ~= "table" then
		return
	end
	for _, entry in ipairs(data.Log) do
		AddLogEntry(entry)
	end
end

-- Dipanggil setelah NEXT WEEK. Placeholder "Loading" diabaikan agar profil tidak ter-reset ke 0.
local function RefreshProfile()
	local ok, data = SafeInvoke(GETDATA_TIMEOUT, "GetData")
	if ok and type(data) == "table" and data.Loading ~= true then
		ApplyProfile(data)
	else
		warn("[DashboardUI] Gagal refresh profil:", data)
	end
end

-- Listener dipasang SEBELUM GetData supaya tidak ada event yang terlewat.
Network:OnClientEvent("StatChanged", function(statName, newValue)
	if not ui then
		return
	end
	local setter = ui.StatSetters[statName]
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
	if serverBusy then
		ArmWatchdog(WATCHDOG_MINIGAME) -- state busy tidak boleh bertahan selamanya di client
	end
	UpdateButtons()
end)

-- NEXT WEEK: invoke aman (pcall + timeout) di task.spawn, tombol SELALU di-reset di akhir.
nextBtn.Activated:Connect(function()
	if serverBusy or localBusy then
		return
	end
	localBusy = true
	UpdateButtons()
	ArmWatchdog(WATCHDOG_NEXT_WEEK)

	task.spawn(function()
		local bodyOk, bodyErr = pcall(function()
			local ok, success, message = SafeInvoke(NEXT_WEEK_TIMEOUT, "NextWeek")
			if not ok then
				warn("[DashboardUI] NextWeek error:", success)
				AddLogEntry({ Text = "Koneksi ke server bermasalah, coba lagi.", Type = "Bahaya", Icon = "⚠️" })
			elseif success == false then
				AddLogEntry({ Text = tostring(message or "Tidak bisa lanjut minggu sekarang."), Type = "Bahaya", Icon = "⚠️" })
			end

			-- Server belum mengirim event umur -> sinkronkan via GetData setelah minggu selesai.
			RefreshProfile()
		end)
		if not bodyOk then
			warn("[DashboardUI] Handler NextWeek crash:", bodyErr)
		end

		ResetButtons() -- selalu jalan: teks kembali "NEXT WEEK ▶", Active = true
	end)
end)

-- Tombol Kerja -> minta OjolRunner membuka mini-game
workBtn.Activated:Connect(function()
	if serverBusy or localBusy then
		return
	end
	localBusy = true -- mengunci kedua tombol sampai mini-game ditutup
	UpdateButtons()
	ArmWatchdog(WATCHDOG_MINIGAME)
	miniGameOpen:Fire("Ojol")
end)

-- Mini-game ditutup (selesai normal atau gagal mulai)
miniGameClosed.Event:Connect(function(errorMessage)
	ResetButtons()
	if errorMessage then
		AddLogEntry({ Text = tostring(errorMessage), Type = "Bahaya", Icon = "⚠️" })
	end
end)

-- Muat data awal: retry selama server masih memuat (placeholder Loading), tidak pernah crash.
task.spawn(function()
	local loaded = false
	local notifiedLoading = false

	for attempt = 1, LOAD_ATTEMPTS do
		local ok, data = SafeInvoke(GETDATA_TIMEOUT, "GetData")
		if ok and type(data) == "table" then
			if data.Loading == true then
				if not notifiedLoading then
					notifiedLoading = true
					AddLogEntry({ Text = "Memuat data, mohon tunggu...", Type = "Info", Icon = "⏳" })
				end
			else
				UpdateStatUI(data)
				AddHistory(data)
				loaded = true
				break
			end
		else
			warn("[DashboardUI] GetData gagal:", data)
		end

		if attempt < LOAD_ATTEMPTS then
			task.wait(LOAD_RETRY_DELAY)
		end
	end

	if not loaded then
		AddLogEntry({ Text = "Gagal memuat data. Coba rejoin.", Type = "Bahaya", Icon = "⚠️" })
	end
end)

UpdateButtons()
screenGui.Parent = playerGui
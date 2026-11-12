--!nonstrict
-- src/client/OjolRunner.client.lua
-- Mini-game Narik Ojol: endless runner 3 jalur, 15 detik, Soft UI.
-- Dashboard berkomunikasi lewat BindableEvent lokal:
--   "MiniGameOpen"   (Dashboard -> Runner) : arg gameType
--   "MiniGameClosed" (Runner -> Dashboard) : arg errorMessage? (nil = selesai normal)
--
-- Catatan sinkronisasi dengan server (MiniGameModule):
--   * Server menolak FinishMiniGame yang datang sebelum (Duration - toleransi).
--     Jadi jika pemain tabrakan lebih awal, game langsung berhenti di layar,
--     tetapi klaim ke server ditunda sampai durasi penuh berlalu.
--   * Server menghitung Cash = skor * RewardPerScore (MaxScore 40).
--     Tampilan skor = koin * 10, tetapi yang dikirim ke server = jumlah koin.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local GuiService        = game:GetService("GuiService")

local Network = require(ReplicatedStorage.Shared.Network)
local UIStyle = require(script.Parent:WaitForChild("UI"):WaitForChild("UIStyle"))

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Colors    = UIStyle.Colors
local Fonts     = UIStyle.Fonts

-- ===== Konstanta =====
local GAME_TYPE        = "Ojol"
local DURATION         = 15      -- detik (samakan dengan MiniGameModule.Duration)
local LANE_COUNT       = 3
local ENTITY_WIDTH     = 0.2     -- lebar entity = 20% lebar area game
local BASE_FALL_SPEED  = 0.55    -- tinggi area per detik di awal
local FALL_ACCEL       = 0.05    -- tambahan kecepatan per detik berjalan
local MAX_FALL_SPEED   = 1.5
local BASE_SPAWN       = 0.6     -- detik antar spawn di awal
local MIN_SPAWN        = 0.32    -- batas interval spawn tercepat
local OBSTACLE_CHANCE  = 0.45
local COIN_POINTS      = 10      -- skor tampilan per koin
local PLAYER_Y         = 0.86    -- posisi vertikal player (skala area)
local LANE_LERP        = 18      -- kecepatan geser player antar jalur
local RESULT_DELAY     = 1.8     -- detik menampilkan hasil sebelum UI ditutup
local CONTROL_HEIGHT   = 56
local HEADER_HEIGHT    = 64
local PILL             = UDim.new(0.5, 0)

-- ===== Bridge ke Dashboard =====
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

local openEvent   = GetBindable("MiniGameOpen")
local closedEvent = GetBindable("MiniGameClosed")

local active = false

local function GetTopInset(): number
	local inset = GuiService:GetGuiInset().Y
	return if inset < 36 then 58 else inset
end

local function LaneX(lane: number): number
	return (lane - 0.5) / LANE_COUNT
end

-- ===== Bangun UI =====
local function BuildUI()
	local screenGui = UIStyle.CreateComponent("ScreenGui", {
		Name = "OjolRunnerUI",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 50,
	})

	-- Overlay hitam semi-transparan (Active = true supaya klik tidak tembus ke dashboard)
	local overlay = UIStyle.CreateComponent("Frame", {
		Name = "Overlay",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Active = true,
		Size = UDim2.fromScale(1, 1),
		Parent = screenGui,
	})

	-- Safe area: tidak tertimpa topbar Roblox
	local safe = UIStyle.CreateComponent("Frame", {
		Name = "Safe",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = overlay,
	}, {
		UIStyle.CreateComponent("UIPadding", {
			PaddingTop = UDim.new(0, GetTopInset() + 8),
			PaddingBottom = UDim.new(0, 16),
			PaddingLeft = UDim.new(0, 16),
			PaddingRight = UDim.new(0, 16),
		}),
	})

	-- Card utama (putih, radius 24)
	local wrapper, card = UIStyle.CreateCard({
		Name = "OjolCard",
		Size = UDim2.fromScale(1, 1),
		Parent = safe,
	})
	wrapper.AnchorPoint = Vector2.new(0.5, 0.5)
	wrapper.Position = UDim2.fromScale(0.5, 0.5)
	UIStyle.CreateComponent("UISizeConstraint", { MaxSize = Vector2.new(460, 700) }).Parent = wrapper

	-- Header: judul, timer, skor
	UIStyle.CreateLabel({
		Name = "Title",
		Text = "Narik Ojol 🛵",
		Font = Fonts.Bold,
		TextSize = UIStyle.TextSize.Title,
		Size = UDim2.new(0.6, 0, 0, 28),
		Parent = card,
	})
	local timerLabel = UIStyle.CreateLabel({
		Name = "Timer",
		Text = ("⏱ %ds"):format(DURATION),
		Font = Fonts.Bold,
		TextSize = UIStyle.TextSize.Title,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.fromScale(0.6, 0),
		Size = UDim2.new(0.4, 0, 0, 28),
		Parent = card,
	})
	local scoreLabel = UIStyle.CreateLabel({
		Name = "Score",
		Text = "🪙 0",
		Font = Fonts.Bold,
		TextSize = 16,
		Position = UDim2.fromOffset(0, 34),
		Size = UDim2.new(0.4, 0, 0, 22),
		Parent = card,
	})
	UIStyle.CreateLabel({
		Name = "Hint",
		Text = "Ambil kuning, hindari merah!",
		TextSize = UIStyle.TextSize.Caption,
		TextColor3 = Colors.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.new(0.4, 0, 0, 34),
		Size = UDim2.new(0.6, 0, 0, 22),
		Parent = card,
	})

	-- Holder: mengisi ruang tengah card; area game di dalamnya dijaga rasio 4:5 (maks 400x500)
	local holder = UIStyle.CreateComponent("Frame", {
		Name = "AreaHolder",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, HEADER_HEIGHT),
		Size = UDim2.new(1, 0, 1, -(HEADER_HEIGHT + CONTROL_HEIGHT + 12)),
		Parent = card,
	})

	-- Area game hitam, 3 jalur vertikal
	local area = UIStyle.CreateComponent("Frame", {
		Name = "GameArea",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Corner = UIStyle.RadiusSmall,
		Parent = holder,
	}, {
		UIStyle.CreateComponent("UIAspectRatioConstraint", {
			AspectRatio = 0.8,
			AspectType = Enum.AspectType.FitWithinMaxSize,
			DominantAxis = Enum.DominantAxis.Width,
		}),
		UIStyle.CreateComponent("UISizeConstraint", { MaxSize = Vector2.new(400, 500) }),
	})
	for i = 1, LANE_COUNT - 1 do
		UIStyle.CreateComponent("Frame", {
			Name = "Divider" .. i,
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0.75,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(i / LANE_COUNT, 0),
			Size = UDim2.new(0, 2, 1, 0),
			ZIndex = 1,
			Parent = area,
		})
	end

	-- Player: frame biru di jalur tengah bagian bawah
	local playerFrame = UIStyle.CreateComponent("Frame", {
		Name = "Player",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Colors.Info,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(LaneX(2), PLAYER_Y),
		Size = UDim2.fromOffset(48, 48),
		ZIndex = 3,
		Corner = 12,
		Parent = area,
	}, {
		UIStyle.CreateLabel({
			Text = "🛵",
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 4,
		}, {
			UIStyle.CreateComponent("UIPadding", { Padding = 6 }),
		}),
	})

	-- Label hasil (tampil saat game selesai)
	local resultLabel = UIStyle.CreateLabel({
		Name = "Result",
		Text = "",
		Font = Fonts.Bold,
		TextSize = 18,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		BackgroundTransparency = 0.05,
		BackgroundColor3 = Colors.Card,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.85, 0, 0, 100),
		Visible = false,
		ZIndex = 10,
		Corner = UIStyle.RadiusSmall,
		Parent = area,
	})

	-- Kontrol on-screen (touch target 56px)
	local function CreateControlButton(text: string, position: UDim2): TextButton
		return UIStyle.CreateComponent("TextButton", {
			Name = "Control" .. text,
			Text = text,
			Font = Fonts.Bold,
			TextSize = 28,
			TextColor3 = Colors.TextLight,
			BackgroundColor3 = Colors.ButtonBlack,
			BorderSizePixel = 0,
			AutoButtonColor = true,
			Position = position,
			Size = UDim2.new(0.5, -6, 1, 0),
			Corner = PILL,
		})
	end
	local leftButton  = CreateControlButton("⬅️", UDim2.fromScale(0, 0))
	local rightButton = CreateControlButton("➡️", UDim2.new(0.5, 6, 0, 0))
	UIStyle.CreateComponent("Frame", {
		Name = "Controls",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 1, -CONTROL_HEIGHT),
		Size = UDim2.new(1, 0, 0, CONTROL_HEIGHT),
		Parent = card,
	}, { leftButton, rightButton })

	return {
		ScreenGui = screenGui,
		Area = area,
		Player = playerFrame,
		TimerLabel = timerLabel,
		ScoreLabel = scoreLabel,
		ResultLabel = resultLabel,
		LeftButton = leftButton,
		RightButton = rightButton,
	}
end

-- Obstacle = kotak merah, Coin = kotak kuning
local function CreateEntity(area: Frame, kind: string, lane: number, cell: number)
	local isCoin = kind == "Coin"
	local frame = UIStyle.CreateComponent("Frame", {
		Name = kind,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = if isCoin then Colors.StatStress else Colors.Danger,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(LaneX(lane), -0.1),
		Size = UDim2.fromOffset(cell, cell),
		ZIndex = 2,
		Corner = if isCoin then PILL else 10,
		Parent = area,
	}, {
		UIStyle.CreateLabel({
			Text = if isCoin then "🪙" else "🚧",
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 3,
		}, {
			UIStyle.CreateComponent("UIPadding", { Padding = 6 }),
		}),
	})
	return { Frame = frame, Kind = kind, Lane = lane, Y = -0.1 }
end

-- ===== Game loop =====
local function Run(ui)
	local area = ui.Area
	local entities = {}
	local connections = {}

	local coins = 0
	local targetLane = 2
	local playerX = LaneX(2)
	local spawnTimer = 0.4
	local lastCell = 0
	local lastSecond = -1
	local finished = false
	local crashed = false
	local startClock = os.clock()

	local function MoveLane(direction: number)
		if finished then
			return
		end
		targetLane = math.clamp(targetLane + direction, 1, LANE_COUNT)
	end

	-- Putuskan SEMUA koneksi (input + loop) agar tidak bocor memori.
	local function Disconnect()
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		table.clear(connections)
	end

	local function SetTimerText(secondsLeft: number)
		ui.TimerLabel.Text = ("⏱ %ds"):format(secondsLeft)
		ui.TimerLabel.TextColor3 = if secondsLeft <= 5 then Colors.Danger else Colors.TextDark
	end

	-- Dipanggil saat timer habis ATAU tabrakan.
	local function Finish(didCrash: boolean)
		if finished then
			return
		end
		finished = true
		crashed = didCrash
		Disconnect() -- loop berhenti, input dilepas

		for _, entity in ipairs(entities) do
			entity.Frame:Destroy()
		end
		table.clear(entities)

		local displayScore = coins * COIN_POINTS
		ui.ResultLabel.TextColor3 = if didCrash then Colors.Danger else Colors.TextDark
		ui.ResultLabel.Text = if didCrash
			then ("💥 Tabrakan!\nSkor %d"):format(displayScore)
			else "Menghitung hasil..."
		ui.ResultLabel.Visible = true

		task.spawn(function()
			-- Server menolak klaim yang datang sebelum durasi penuh (anti-cheat),
			-- jadi jika tabrakan lebih awal, tunggu sisa waktu sebelum klaim.
			while os.clock() - startClock < DURATION do
				SetTimerText(math.max(0, math.ceil(DURATION - (os.clock() - startClock))))
				task.wait(0.1)
			end
			SetTimerText(0)
			ui.ResultLabel.Text = "Menghitung hasil..."
			ui.ResultLabel.TextColor3 = Colors.TextDark

			-- Server menghitung reward dari jumlah koin (skor tampilan = koin x 10).
			local ok, success, reward, message = pcall(function()
				return Network:InvokeServer("FinishMiniGame", GAME_TYPE, coins)
			end)

			local closeMessage = nil
			if ok and success == true then
				local prefix = if crashed then "Tabrakan! " else "Selesai! "
				ui.ResultLabel.Text = ("%sSkor %d\n+%s"):format(prefix, displayScore, UIStyle.FormatRupiah(reward or 0))
				ui.ResultLabel.TextColor3 = Colors.TextMoney
			else
				closeMessage = if ok and type(message) == "string" then message else "Koneksi ke server bermasalah."
				ui.ResultLabel.Text = closeMessage
				ui.ResultLabel.TextColor3 = Colors.Danger
			end

			task.wait(RESULT_DELAY)
			ui.ScreenGui:Destroy()
			active = false
			closedEvent:Fire(closeMessage)
		end)
	end

	-- Input keyboard (panah / A-D)
	table.insert(connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or finished then
			return
		end
		if input.KeyCode == Enum.KeyCode.Left or input.KeyCode == Enum.KeyCode.A then
			MoveLane(-1)
		elseif input.KeyCode == Enum.KeyCode.Right or input.KeyCode == Enum.KeyCode.D then
			MoveLane(1)
		end
	end))
	-- Input on-screen
	table.insert(connections, ui.LeftButton.Activated:Connect(function() MoveLane(-1) end))
	table.insert(connections, ui.RightButton.Activated:Connect(function() MoveLane(1) end))

	-- Loop utama
	table.insert(connections, RunService.RenderStepped:Connect(function(dtRaw)
		if finished then
			return
		end
		local dt = math.min(dtRaw, 0.1) -- cegah lompatan saat lag
		local now = os.clock()
		local elapsed = now - startClock
		local timeLeft = DURATION - elapsed
		if timeLeft <= 0 then
			Finish(false)
			return
		end

		-- Timer
		local secondsLeft = math.ceil(timeLeft)
		if secondsLeft ~= lastSecond then
			lastSecond = secondsLeft
			SetTimerText(secondsLeft)
		end

		local areaSize = area.AbsoluteSize
		if areaSize.X <= 0 or areaSize.Y <= 0 then
			return
		end

		-- Ukuran entity mengikuti lebar area (responsive)
		local cell = math.floor(areaSize.X * ENTITY_WIDTH)
		if cell ~= lastCell then
			lastCell = cell
			ui.Player.Size = UDim2.fromOffset(cell, cell)
			for _, entity in ipairs(entities) do
				entity.Frame.Size = UDim2.fromOffset(cell, cell)
			end
		end

		-- Geser player halus ke jalur target
		playerX += (LaneX(targetLane) - playerX) * math.min(1, dt * LANE_LERP)
		ui.Player.Position = UDim2.fromScale(playerX, PLAYER_Y)

		-- Kecepatan jatuh & laju spawn naik seiring waktu
		local fallSpeed = math.min(MAX_FALL_SPEED, BASE_FALL_SPEED + FALL_ACCEL * elapsed)
		local spawnInterval = math.max(MIN_SPAWN, BASE_SPAWN - 0.02 * elapsed)

		-- Spawn (satu entity per tick -> tidak pernah menutup ketiga jalur sekaligus)
		spawnTimer -= dt
		if spawnTimer <= 0 then
			spawnTimer += spawnInterval
			local kind = if math.random() < OBSTACLE_CHANCE then "Obstacle" else "Coin"
			table.insert(entities, CreateEntity(area, kind, math.random(1, LANE_COUNT), cell))
		end

		-- Gerak + tabrakan
		local hitRadius = (cell * 0.85) / areaSize.Y
		local crashNow = false
		for i = #entities, 1, -1 do
			local entity = entities[i]
			entity.Y += fallSpeed * dt
			entity.Frame.Position = UDim2.fromScale(LaneX(entity.Lane), entity.Y)

			local remove = entity.Y > 1.15
			if not remove and entity.Lane == targetLane and math.abs(entity.Y - PLAYER_Y) < hitRadius then
				if entity.Kind == "Coin" then
					coins += 1
					remove = true
				else
					crashNow = true -- tabrakan -> game langsung berakhir
				end
			end

			if remove then
				entity.Frame:Destroy()
				table.remove(entities, i)
			end
		end

		ui.ScoreLabel.Text = "🪙 " .. (coins * COIN_POINTS)

		if crashNow then
			Finish(true)
		end
	end))
end

-- ===== Start =====
local function Start()
	if active then
		return
	end
	active = true

	local ok, success, message = pcall(function()
		return Network:InvokeServer("StartMiniGame", GAME_TYPE)
	end)
	if not ok or success ~= true then
		active = false
		closedEvent:Fire(if ok and type(message) == "string" then message else "Tidak bisa memulai mini-game.")
		return
	end

	local ui = BuildUI()
	ui.ScreenGui.Parent = playerGui
	Run(ui)
end

openEvent.Event:Connect(function(gameType)
	if gameType == GAME_TYPE then
		task.spawn(Start)
	end
end)
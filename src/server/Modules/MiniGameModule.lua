--!strict
-- Framework mini-game sisi server.
-- Alur: StartGame (buka sesi) -> client main -> FinishGame (validasi, reward, stat, log).
-- Client TIDAK dipercaya: skor di-clamp, durasi dicek, dan satu sesi hanya bisa di-claim sekali.

local StatSystem  = require(script.Parent.StatSystem)
local LogSystem   = require(script.Parent.LogSystem)
local DataManager = require(script.Parent.DataManager)

export type GameDef = {
	Name: string,
	Icon: string,
	Duration: number,       -- detik
	MaxScore: number,       -- batas atas skor yang masuk akal (anti-cheat)
	RewardPerScore: number, -- Cash += score * RewardPerScore
	StressGain: number,
}

type Session = {
	GameType: string,
	StartedAt: number,
}

local GAMES: { [string]: GameDef } = {
	Ojol = {
		Name = "Narik Ojol",
		Icon = "🛵",
		Duration = 15,
		MaxScore = 40,
		RewardPerScore = 10,
		StressGain = 5,
	},
}

local TIME_TOLERANCE = 1.5 -- detik; toleransi latency saat cek durasi minimum
local EXPIRE_GRACE   = 10  -- detik; sesi yang tidak diselesaikan client akan hangus

local sessions: { [number]: Session } = {}

local MiniGameModule = {}

local function FormatRupiah(amount: number): string
	local digits = string.format("%d", math.floor(math.abs(amount)))
	local withDots = string.gsub(string.reverse(digits), "(%d%d%d)", "%1.")
	local result = string.reverse(withDots)
	if string.sub(result, 1, 1) == "." then
		result = string.sub(result, 2)
	end
	return "Rp" .. result
end

function MiniGameModule:GetDef(gameType: any): GameDef?
	if type(gameType) ~= "string" then
		return nil
	end
	return GAMES[gameType]
end

-- Buka sesi. `onExpire` dipanggil jika client tidak pernah menyelesaikan sesi (crash / exploit).
function MiniGameModule:StartGame(player: Player, gameType: any, onExpire: ((Player) -> ())?): (boolean, string?)
	local def = self:GetDef(gameType)
	if not def then
		return false, "Mini-game tidak dikenal."
	end
	if not DataManager:Get(player) then
		return false, "Data belum siap."
	end

	local userId = player.UserId
	if sessions[userId] then
		return false, "Mini-game sedang berjalan."
	end

	local session: Session = { GameType = gameType :: string, StartedAt = os.clock() }
	sessions[userId] = session

	task.delay(def.Duration + EXPIRE_GRACE, function()
		if sessions[userId] == session then
			sessions[userId] = nil
			if onExpire then
				onExpire(player)
			end
		end
	end)
	return true, nil
end

-- Mengembalikan (berhasil, reward, pesan error?).
function MiniGameModule:FinishGame(player: Player, gameType: any, score: any): (boolean, number, string?)
	local userId = player.UserId
	local session = sessions[userId]
	if not session then
		return false, 0, "Tidak ada mini-game aktif."
	end
	sessions[userId] = nil -- sesi sekali pakai

	if gameType ~= session.GameType then
		return false, 0, "Tipe mini-game tidak cocok."
	end
	local def = GAMES[session.GameType]

	if os.clock() - session.StartedAt < def.Duration - TIME_TOLERANCE then
		warn(("[MiniGame] %s selesai terlalu cepat, ditolak."):format(player.Name))
		return false, 0, "Mini-game selesai terlalu cepat."
	end
	if not DataManager:Get(player) then
		return false, 0, "Data belum siap."
	end

	-- Sanitasi skor: harus angka valid, bulat, dalam batas.
	local safeScore = 0
	if type(score) == "number" and score == score then
		safeScore = math.clamp(math.floor(score), 0, def.MaxScore)
	end

	local reward = safeScore * def.RewardPerScore
	StatSystem:Modify(player, "Cash", reward, def.Name)
	StatSystem:Modify(player, "Stress", def.StressGain, "Kerja " .. def.Name)
	LogSystem:Add(player, ("Selesai %s, dapat %s"):format(def.Name, FormatRupiah(reward)), "Uang", def.Icon)

	return true, reward, nil
end

-- Hapus sesi (dipakai saat player keluar).
function MiniGameModule:Cancel(player: Player)
	sessions[player.UserId] = nil
end

return MiniGameModule
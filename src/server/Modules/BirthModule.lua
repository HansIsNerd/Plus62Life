--!strict
-- src/server/Modules/BirthModule.lua
-- RNG kelahiran: menentukan kelas sosial awal pemain dan menerapkan stat awalnya.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataManager = require(script.Parent.DataManager)
local StatSystem  = require(script.Parent.StatSystem)
local LogSystem   = require(script.Parent.LogSystem)

local BirthModule = {}

type BirthClass = {
	Id: string,
	Weight: number,
	Cash: number,
	Stress: number,
	Reputation: number,
	LogText: string,
	LogType: string,
	LogIcon: string,
}

-- Total bobot = 100 (50 + 45 + 5), jadi bobot sekaligus persentase.
local BIRTH_CLASSES: { BirthClass } = {
	{
		Id = "Kere", Weight = 50,
		Cash = 0, Stress = 50, Reputation = 20,
		LogText = "Lahir di keluarga broken home. Hidup susah!",
		LogType = "Bahaya", LogIcon = "🏚️",
	},
	{
		Id = "Menengah", Weight = 45,
		Cash = 500, Stress = 10, Reputation = 50,
		LogText = "Lahir di keluarga menengah. Hidup cukup.",
		LogType = "Info", LogIcon = "🏠",
	},
	{
		Id = "Sultan", Weight = 5,
		Cash = 5000, Stress = 0, Reputation = 80,
		LogText = "Lahir sebagai anak sultan! Berlimpah harta.",
		LogType = "Success", LogIcon = "👑",
	},
}

local rng = Random.new()

-- Weighted random: acak 0..totalBobot, lalu cari kelas yang rentang kumulatifnya mengandung angka itu.
local function PickBirthClass(): BirthClass
	local totalWeight = 0
	for _, birthClass in ipairs(BIRTH_CLASSES) do
		totalWeight += birthClass.Weight
	end

	local roll = rng:NextNumber() * totalWeight
	local cumulative = 0
	for _, birthClass in ipairs(BIRTH_CLASSES) do
		cumulative += birthClass.Weight
		if roll < cumulative then
			return birthClass
		end
	end
	return BIRTH_CLASSES[#BIRTH_CLASSES] -- pengaman untuk error pembulatan float
end

-- StatSystem:Modify bekerja dengan selisih (delta), jadi nilai absolut dikonversi dulu.
local function SetStat(player: Player, statName: string, target: number, reason: string)
	local current = StatSystem:Get(player, statName)
	local delta = target - current
	if delta ~= 0 then
		StatSystem:Modify(player, statName, delta, reason)
	end
end

-- Mengembalikan Id kelas ("Kere" | "Menengah" | "Sultan"), atau nil jika data pemain belum ada.
function BirthModule:RollBirth(player: Player): string?
	local data: any = DataManager:Get(player)
	if not data then
		warn(("[BirthModule] Data %s belum dimuat."):format(player.Name))
		return nil
	end

	-- Pengaman: pemain yang keluar sebelum minggu pertama (Week masih 0) tidak boleh reroll kelahiran.
	if data.Flags.BirthRolled then
		return data.Flags.BirthClass
	end

	local birthClass = PickBirthClass()

	SetStat(player, "Cash", birthClass.Cash, "Kelahiran")
	SetStat(player, "Stress", birthClass.Stress, "Kelahiran")
	SetStat(player, "Reputation", birthClass.Reputation, "Kelahiran")

	data.Flags.BirthRolled = true
	data.Flags.BirthClass = birthClass.Id

	LogSystem:Add(player, birthClass.LogText, birthClass.LogType, birthClass.LogIcon)
	return birthClass.Id
end

return BirthModule
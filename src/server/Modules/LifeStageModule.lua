--!strict
-- src/server/Modules/LifeStageModule.lua
-- Menentukan life stage dari umur dan memberi notifikasi saat pemain pindah stage.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config      = require(ReplicatedStorage.Shared.Config)
local DataManager = require(script.Parent.DataManager)
local LogSystem   = require(script.Parent.LogSystem)

local LifeStageModule = {}

type StageMessage = { Text: string, Icon: string }

-- Definisi rentang umur ada di Config.LifeStages:
-- Bayi (0-5), Anak (6-18), Dewasa (19-24), Kerja (25-50), Pensiun (51+).
local STAGE_MESSAGES: { [string]: StageMessage } = {
	Bayi    = { Text = "Kamu lahir ke dunia. Selamat datang!", Icon = "👶" },
	Anak    = { Text = "Kamu mulai bersekolah! Waktunya belajar.", Icon = "🎒" },
	Dewasa  = { Text = "Kamu beranjak dewasa!", Icon = "🧑" },
	Kerja   = { Text = "Selamat datang di dunia kerja. Siap-siap hadapi cicilan!", Icon = "💼" },
	Pensiun = { Text = "Kamu memasuki masa pensiun.", Icon = "👴" },
}

-- Mengembalikan nama stage untuk umur tertentu. Umur di luar semua rentang jatuh ke stage terakhir.
function LifeStageModule:GetStageForAge(age: number): string
	local stages = Config.LifeStages
	for _, stage in ipairs(stages) do
		if age >= stage.MinAge and age <= stage.MaxAge then
			return stage.Name
		end
	end
	return stages[#stages].Name
end

-- Mengembalikan true jika pemain pindah ke stage baru (data.LifeStage diperbarui + log dikirim).
function LifeStageModule:CheckStage(player: Player, age: number): boolean
	local data: any = DataManager:Get(player)
	if not data then
		return false
	end

	local newStage = LifeStageModule:GetStageForAge(age)
	if data.LifeStage == newStage then
		return false
	end

	data.LifeStage = newStage

	local message = STAGE_MESSAGES[newStage]
	if message then
		LogSystem:Add(player, message.Text, "Event", message.Icon)
	end
	return true
end

return LifeStageModule
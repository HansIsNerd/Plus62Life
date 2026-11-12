--!nonstrict
local Config      = require(game.ReplicatedStorage.Shared.Config)
local Network     = require(game.ReplicatedStorage.Shared.Network)
local DataManager = require(script.Parent.DataManager)
local StatSystem  = require(script.Parent.StatSystem)
local LogSystem   = require(script.Parent.LogSystem)

local TimeSystem = {}

function TimeSystem:AdvanceWeek(player)
    local data = DataManager:Get(player)
    if not data then return end

    data.Week += 1

    -- 1. Cek Kenaikan Umur (1 Tahun = 4 Minggu)
    local ageWeeks = data.Week % Config.WeeksPerYear
    if ageWeeks == 0 then
        data.Age += 1
        LogSystem:Add(player, ("Selamat ulang tahun! Kamu sekarang berumur %d tahun."):format(data.Age), "Success", "🎂")
        
        -- (Nanti di Fase 3: Update LifeStage di sini)
    end

    -- 2. Simulasi 4 Fase Mingguan
    for _, phase in ipairs(Config.Phases) do
        Network:FireClient("PhaseChanged", player, phase)
        
        if phase == "Senin-Kamis" then
            -- Hari kerja biasa, Stress naik sedikit
            StatSystem:Modify(player, "Stress", 5, "Aktivitas Harian")
            
        elseif phase == "Jumat" then
            -- PAYDAY! (Untuk testing, kita kasih gaji 500/minggu)
            StatSystem:Modify(player, "Cash", 500, "Gaji Mingguan")
            LogSystem:Add(player, "Payday! Gaji masuk: Rp500", "Uang", "💸")
            
        elseif phase == "Sabtu" then
            -- BILLS! (Untuk testing, tagihan kos 300/minggu)
            StatSystem:Modify(player, "Cash", -300, "Tagihan Kos")
            LogSystem:Add(player, "Bayar tagihan kos: -Rp300", "Uang", "🧾")
            
        elseif phase == "Minggu" then
            -- HEALING! (Stress turun, Health naik)
            StatSystem:Modify(player, "Stress", -15, "Istirahat")
            StatSystem:Modify(player, "Health", 5, "Istirahat")
            LogSystem:Add(player, "Hari Minggu! Kamu istirahat dan healing.", "Info", "🛌")
        end
        
        task.wait(0.5) -- Jeda animasi per fase biar kerasa
    end
end

return TimeSystem
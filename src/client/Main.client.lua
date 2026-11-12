--!nonstrict
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player  = Players.LocalPlayer
local Network = require(ReplicatedStorage.Shared.Network)

print("[Client] Warga +62 client started.")

-- Listener untuk perubahan stat
Network:OnClientEvent("StatChanged", function(statName, newValue, reason)
    print(("[UI Update] %s berubah menjadi %s (Alasan: %s)"):format(statName, tostring(newValue), reason or "None"))
end)

-- Listener untuk log baru
Network:OnClientEvent("LogAdded", function(logEntry)
    print(("[UI Log] %s %s"):format(logEntry.Icon, logEntry.Text))
end)

-- Listener untuk pergantian fase mingguan
Network:OnClientEvent("PhaseChanged", function(phase)
    print(("[Phase] Sekarang masuk fase: %s"):format(phase))
end)

-- Ambil data awal pas join
task.spawn(function()
    local ok, data = pcall(function() return Network:InvokeServer("GetData") end)
    if ok and data then
        print(("[Client] Data loaded | Cash=%d Health=%d Stress=%d"):format(
            data.Stats.Cash, data.Stats.Health, data.Stats.Stress))
    end
end)
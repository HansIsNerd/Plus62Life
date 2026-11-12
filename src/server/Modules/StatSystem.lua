--!nonstrict
local Config      = require(game.ReplicatedStorage.Shared.Config)
local Network     = require(game.ReplicatedStorage.Shared.Network)
local DataManager = require(script.Parent.DataManager)

local StatSystem = {}

function StatSystem:Modify(player, statName, amount, reason)
    local data = DataManager:Get(player)
    if not data or not data.Stats[statName] then return end

    local conf = Config.Stats[statName]
    local oldValue = data.Stats[statName]
    
    -- Hitung nilai baru & clamp (jangan sampai minus/lebih dari max)
    local newValue = math.clamp(oldValue + amount, conf.Min, conf.Max)
    data.Stats[statName] = newValue

    -- Kirim update ke Client (nanti dipake UI)
    Network:FireClient("StatChanged", player, statName, newValue, reason)

    -- Cek kondisi Stress max
    if statName == "Stress" and newValue >= 100 then
        -- Nanti di fase event, kita trigger Burnout di sini
        warn(("[StatSystem] %s mengalami Burnout (Stress 100)!"):format(player.Name))
    end

    return newValue
end

function StatSystem:Get(player, statName)
    local data = DataManager:Get(player)
    return data and data.Stats[statName] or 0
end

return StatSystem
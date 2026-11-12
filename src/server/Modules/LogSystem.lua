--!nonstrict
local Network     = require(game.ReplicatedStorage.Shared.Network)
local DataManager = require(script.Parent.DataManager)

local LogSystem = {}

-- Tipe log: "Info", "Uang", "Bahaya", "Event", "Success"
function LogSystem:Add(player, text, logType, icon)
    local data = DataManager:Get(player)
    if not data then return end

    local entry = {
        Text = text,
        Type = logType or "Info",
        Icon = icon or "📝",
        Week = data.Week,
        Time = os.time()
    }

    -- Simpan ke history (max 100)
    table.insert(data.Log, entry)
    if #data.Log > 100 then
        table.remove(data.Log, 1)
    end

    -- Kirim ke client (untuk UI nanti)
    Network:FireClient("LogAdded", player, entry)
    
    -- Print ke console biar kita bisa liat di Studio
    print(("[LOG - %s] %s"):format(player.Name, text))
end

return LogSystem
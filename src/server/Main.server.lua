--!nonstrict
-- src/server/Main.server.lua
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules         = script.Parent.Modules
local Network         = require(ReplicatedStorage.Shared.Network)
local DataManager     = require(Modules.DataManager)
local TimeSystem      = require(Modules.TimeSystem)
local BirthModule     = require(Modules.BirthModule)
local GameState       = require(ReplicatedStorage.Shared.GameState)

DataManager:Init()

-- Simpan state game per player (IDLE, WEEK_PHASE, dll)
local playerStates = {}
local function setState(player, state)
    playerStates[player.UserId] = state
    Network:FireClient("GameStateChanged", player, state)
end

Network:OnServerInvoke("GetData", function(player)
    local data = DataManager:Get(player)
    local t = os.clock()
    while not data and (os.clock() - t) < 5 do
        task.wait(0.1); data = DataManager:Get(player)
    end
    return data
end)

-- TEST NEXT WEEK (Nanti dipanggil dari tombol UI)
Network:OnServerInvoke("NextWeek", function(player)
    -- Cek state biar ga bisa spam klik
    if playerStates[player.UserId] ~= GameState.State.IDLE and playerStates[player.UserId] ~= nil then
        return false, "Sedang sibuk!"
    end

    setState(player, GameState.State.WEEK_PHASE)
    
    -- Jalankan mesin waktu
    TimeSystem:AdvanceWeek(player)
    
    setState(player, GameState.State.IDLE)
    return true
end)

Players.PlayerAdded:Connect(function(player)
    playerStates[player.UserId] = GameState.State.IDLE
    local data = DataManager:Load(player)
    if not data then player:Kick("Gagal memuat data."); return end
    print(("[Server] Loaded %s | Stage=%s | Age=%d"):format(player.Name, data.LifeStage, data.Age))

    -- Fase 3: pemain baru (Week == 0) -> RNG kelahiran.
    -- BirthModule punya flag BirthRolled, jadi keluar-masuk sebelum minggu pertama tidak bisa reroll.
    if data.Week == 0 then
        local ok, err = pcall(function()
            BirthModule:RollBirth(player)
        end)
        if not ok then
            warn(("[Server] RollBirth gagal untuk %s: %s"):format(player.Name, tostring(err)))
        end
    end
end)

Players.PlayerRemoving:Connect(function(player)
    DataManager:Save(player, true)
    playerStates[player.UserId] = nil
end)

game:BindToClose(function()
    for _, p in ipairs(Players:GetPlayers()) do DataManager:Save(p, true) end
    task.wait(2)
end)

local C = require(ReplicatedStorage.Shared.Config)
print(("[Server] %s v%s Engine Started."):format(C.GameName, C.Version))
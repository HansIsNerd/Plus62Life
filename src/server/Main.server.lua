--!nonstrict
-- src/server/Main.server.lua
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules         = script.Parent.Modules
local Network         = require(ReplicatedStorage.Shared.Network)
local DataManager     = require(Modules.DataManager)
local TimeSystem      = require(Modules.TimeSystem)
local BirthModule     = require(Modules.BirthModule)
local LogSystem       = require(Modules.LogSystem)
local MiniGameModule  = require(Modules.MiniGameModule)
local GameState       = require(ReplicatedStorage.Shared.GameState)

local GETDATA_MAX_WAIT = 3 -- detik; GetData tidak boleh menggantung lebih lama dari ini

DataManager:Init()

local playerStates   = {} -- [userId] = GameState.State.*
local loadingPlayers = {} -- [userId] = true selama DataManager:Load berjalan
local initialized    = {} -- [userId] = true; cegah init ganda

local function setState(player, state)
    -- Jangan buat entri baru untuk pemain yang sudah keluar (hindari memory leak).
    if player.Parent ~= Players then return end
    playerStates[player.UserId] = state
    pcall(function()
        Network:FireClient("GameStateChanged", player, state)
    end)
end

local function isIdle(player)
    local state = playerStates[player.UserId]
    return state == nil or state == GameState.State.IDLE
end

-- GetData: tidak pernah yield lama dan tidak pernah mengembalikan nil.
-- Jika data belum siap -> placeholder default dengan Loading = true (client akan retry).
Network:OnServerInvoke("GetData", function(player)
    local data = DataManager:Get(player)
    if data then return data end

    local startClock = os.clock()
    while not data and loadingPlayers[player.UserId] and (os.clock() - startClock) < GETDATA_MAX_WAIT do
        task.wait(0.1)
        data = DataManager:Get(player)
    end
    if data then return data end

    local fallback = DataManager:CreateDefault()
    fallback.Loading = true
    return fallback
end)

-- NEXT WEEK: state SELALU kembali ke IDLE, walau AdvanceWeek error.
Network:OnServerInvoke("NextWeek", function(player)
    if not DataManager:Get(player) then
        return false, "Data masih dimuat, tunggu sebentar."
    end
    if not isIdle(player) then
        return false, "Sedang sibuk!"
    end

    setState(player, GameState.State.WEEK_PHASE)
    local ok, err = pcall(function()
        TimeSystem:AdvanceWeek(player)
    end)
    setState(player, GameState.State.IDLE) -- wajib, sukses maupun gagal

    if not ok then
        warn(("[Server] AdvanceWeek error untuk %s: %s"):format(player.Name, tostring(err)))
        return false, "Terjadi kesalahan saat memproses minggu."
    end
    return true
end)

-- Mini-game: handler yang sebelumnya belum terdaftar (penyebab client menggantung).
Network:OnServerInvoke("StartMiniGame", function(player, gameType)
    if not isIdle(player) then
        return false, "Sedang sibuk!"
    end

    local ok, success, message = pcall(function()
        return MiniGameModule:StartGame(player, gameType, function(p)
            setState(p, GameState.State.IDLE) -- sesi hangus -> bebaskan state
        end)
    end)
    if not ok then
        warn(("[Server] StartGame error untuk %s: %s"):format(player.Name, tostring(success)))
        return false, "Gagal memulai mini-game."
    end
    if success then
        setState(player, GameState.State.MINIGAME)
    end
    return success, message
end)

Network:OnServerInvoke("FinishMiniGame", function(player, gameType, score)
    local ok, success, reward, message = pcall(function()
        return MiniGameModule:FinishGame(player, gameType, score)
    end)
    setState(player, GameState.State.IDLE) -- selalu bebaskan state

    if not ok then
        warn(("[Server] FinishGame error untuk %s: %s"):format(player.Name, tostring(success)))
        return false, 0, "Gagal menyelesaikan mini-game."
    end
    return success, reward, message
end)

local function onPlayerAdded(player)
    local uid = player.UserId
    if initialized[uid] then return end
    initialized[uid] = true

    playerStates[uid] = GameState.State.IDLE
    loadingPlayers[uid] = true

    -- Load dibungkus pcall; gagal total pun TIDAK mengeluarkan pemain.
    local ok, result = pcall(function()
        return DataManager:Load(player)
    end)
    local data = if ok then result else nil
    if not ok then
        warn(("[Server] Load error untuk %s: %s"):format(player.Name, tostring(result)))
    end

    -- Pemain keluar saat loading -> bersihkan (Save melewati DataStore untuk data sementara).
    if player.Parent ~= Players then
        DataManager:Save(player, true)
        loadingPlayers[uid] = nil
        initialized[uid] = nil
        playerStates[uid] = nil
        return
    end

    if not data then
        data = DataManager:Get(player) or DataManager:CreateTemporary(player)
    end
    loadingPlayers[uid] = nil

    print(("[Server] Loaded %s | Stage=%s | Age=%d | Temporary=%s"):format(
        player.Name, tostring(data.LifeStage), data.Age or 0, tostring(data.IsTemporary == true)))

    -- Pemain baru (Week == 0) -> RNG kelahiran (punya flag BirthRolled, aman dari reroll).
    if data.Week == 0 then
        local birthOk, birthErr = pcall(function()
            BirthModule:RollBirth(player)
        end)
        if not birthOk then
            warn(("[Server] RollBirth gagal untuk %s: %s"):format(player.Name, tostring(birthErr)))
        end
    end

    if data.IsTemporary then
        LogSystem:Add(player, "Data sementara dipakai. Progres sesi ini tidak akan disimpan.", "Bahaya", "⚠️")
    end
end

Players.PlayerAdded:Connect(function(player)
    task.spawn(onPlayerAdded, player)
end)

-- Pemain yang sudah ada sebelum script ini jalan (mis. Studio) tetap diproses.
for _, player in ipairs(Players:GetPlayers()) do
    task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
    local uid = player.UserId
    pcall(function() MiniGameModule:Cancel(player) end)
    DataManager:Save(player, true)
    playerStates[uid] = nil
    loadingPlayers[uid] = nil
    initialized[uid] = nil
end)

game:BindToClose(function()
    for _, p in ipairs(Players:GetPlayers()) do DataManager:Save(p, true) end
    task.wait(2)
end)

local C = require(ReplicatedStorage.Shared.Config)
print(("[Server] %s v%s Engine Started."):format(C.GameName, C.Version))
--!nonstrict
local DataStoreService = game:GetService("DataStoreService")
local Players          = game:GetService("Players")
local Config           = require(game.ReplicatedStorage.Shared.Config)

local DataManager = {}
local dataStore    = DataStoreService:GetDataStore(Config.DataStoreName)
local sessionStore = DataStoreService:GetDataStore(Config.SessionLockName)
local playerData, sessionLocks = {}, {}

local function defaultData()
    return {
        Version = 1,
        Stats   = {
            Cash       = Config.Stats.Cash.Default,
            Health     = Config.Stats.Health.Default,
            Stress     = Config.Stats.Stress.Default,
            Reputation = Config.Stats.Reputation.Default,
            Debt       = Config.Stats.Debt.Default,
        },
        Log = {}, Inventory = {}, Debts = {},
        LifeStage = "Bayi", Age = 0, Week = 0,
        Flags = {}, LastPlayed = os.time(),
    }
end

local function generateLockId()
    return string.format("%s:%d:%d", game.JobId, os.time(), math.random(1, 1e9))
end

local function tryAcquireLock(userId)
    local lockId = generateLockId()
    local ok, err = pcall(function()
        local existing = sessionStore:GetAsync("lock_" .. userId)
        if existing and (os.time() - existing.Heartbeat) < 60 then
            error("Session locked")
        end
        sessionStore:SetAsync("lock_" .. userId, { LockId = lockId, Heartbeat = os.time() })
    end)
    if not ok then return nil, err end
    return lockId
end

local function refreshLock(userId, lockId)
    pcall(function()
        local cur = sessionStore:GetAsync("lock_" .. userId)
        if cur and cur.LockId == lockId then
            sessionStore:SetAsync("lock_" .. userId, { LockId = lockId, Heartbeat = os.time() })
        end
    end)
end

local function releaseLock(userId, lockId)
    pcall(function()
        local cur = sessionStore:GetAsync("lock_" .. userId)
        if cur and cur.LockId == lockId then sessionStore:RemoveAsync("lock_" .. userId) end
    end)
end

function DataManager:Init()
    task.spawn(function()
        while true do
            task.wait(Config.AutoSaveInterval)
            for _, p in ipairs(Players:GetPlayers()) do
                if playerData[p.UserId] then self:Save(p, false) end
            end
        end
    end)
    task.spawn(function()
        while true do
            task.wait(30)
            for uid, lock in pairs(sessionLocks) do refreshLock(uid, lock.LockId) end
        end
    end)
end

function DataManager:Load(player)
    local uid = player.UserId
    local lockId, err = tryAcquireLock(uid)
    if not lockId then warn("[DM] lock fail:", err); return nil end
    sessionLocks[uid] = { LockId = lockId }

    local ok, data = pcall(function() return dataStore:GetAsync(tostring(uid)) end)
    if not ok then
        warn("[DM] load fail:", data)
        releaseLock(uid, lockId); sessionLocks[uid] = nil
        return nil
    end

    if not data then data = defaultData()
    else
        local def = defaultData()
        for k, v in pairs(def) do if data[k] == nil then data[k] = v end end
        for k, v in pairs(def.Stats) do if data.Stats[k] == nil then data.Stats[k] = v end end
    end

    playerData[uid] = data
    return data
end

function DataManager:Get(player) return playerData[player.UserId] end

function DataManager:Save(player, release)
    local uid, data = player.UserId, playerData[player.UserId]
    if not data then return end
    data.LastPlayed = os.time()
    local ok, err = pcall(function() dataStore:SetAsync(tostring(uid), data) end)
    if not ok then warn("[DM] save fail:", err) end
    if release then
        local lock = sessionLocks[uid]
        if lock then releaseLock(uid, lock.LockId); sessionLocks[uid] = nil end
        playerData[uid] = nil
    end
end

return DataManager
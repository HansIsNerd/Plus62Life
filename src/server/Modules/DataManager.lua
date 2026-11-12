--!nonstrict
local DataStoreService = game:GetService("DataStoreService")
local Players          = game:GetService("Players")
local Config           = require(game.ReplicatedStorage.Shared.Config)

local DataManager = {}
local dataStore    = DataStoreService:GetDataStore(Config.DataStoreName)
local sessionStore = DataStoreService:GetDataStore(Config.SessionLockName)
local playerData, sessionLocks = {}, {}

local MAX_LOCK_ATTEMPTS = 3   -- maksimal percobaan ambil session lock
local LOCK_RETRY_DELAY  = 3   -- detik jeda antar percobaan
local LOCK_STALE_AFTER  = 60  -- detik; lock dianggap basi jika heartbeat lebih lama dari ini

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
        if existing and (os.time() - (existing.Heartbeat or 0)) < LOCK_STALE_AFTER then
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

-- Salinan data default segar (dipakai Main.server sebagai placeholder GetData).
function DataManager:CreateDefault()
    return defaultData()
end

-- Data Sementara: pemain tetap bisa main, tapi TIDAK pernah di-save ke DataStore
-- (supaya tidak menimpa progres asli yang gagal dimuat).
function DataManager:CreateTemporary(player)
    local data = defaultData()
    data.IsTemporary = true
    playerData[player.UserId] = data
    warn(("[DM] %s memakai Data Sementara (progres tidak disimpan)."):format(player.Name))
    return data
end

-- Hampir tidak pernah mengembalikan nil: gagal lock / gagal baca -> Data Sementara.
-- Hanya mengembalikan nil jika pemain sudah keluar saat proses berlangsung.
function DataManager:Load(player)
    local uid = player.UserId
    if playerData[uid] then return playerData[uid] end -- sudah dimuat

    -- 1. Ambil session lock dengan retry
    local lockId, lockErr = nil, nil
    for attempt = 1, MAX_LOCK_ATTEMPTS do
        lockId, lockErr = tryAcquireLock(uid)
        if lockId then break end

        warn(("[DM] lock fail (%d/%d) %s: %s"):format(attempt, MAX_LOCK_ATTEMPTS, player.Name, tostring(lockErr)))
        if attempt < MAX_LOCK_ATTEMPTS then
            task.wait(LOCK_RETRY_DELAY)
            if player.Parent ~= Players then return nil end
        end
    end

    if not lockId then
        if player.Parent ~= Players then return nil end
        return self:CreateTemporary(player)
    end

    if player.Parent ~= Players then
        releaseLock(uid, lockId)
        return nil
    end
    sessionLocks[uid] = { LockId = lockId }

    -- 2. Baca data
    local ok, data = pcall(function() return dataStore:GetAsync(tostring(uid)) end)
    if not ok then
        warn("[DM] load fail:", data)
        releaseLock(uid, lockId); sessionLocks[uid] = nil
        return self:CreateTemporary(player)
    end

    -- 3. Merge dengan default (migrasi field baru)
    local def = defaultData()
    if type(data) ~= "table" then
        data = def
    else
        for k, v in pairs(def) do if data[k] == nil then data[k] = v end end
        if type(data.Stats) ~= "table" then data.Stats = def.Stats end
        for k, v in pairs(def.Stats) do if data.Stats[k] == nil then data.Stats[k] = v end end
    end
    data.IsTemporary = nil -- data asli tidak boleh ikut ter-flag sementara

    playerData[uid] = data
    return data
end

function DataManager:Get(player) return playerData[player.UserId] end

function DataManager:Save(player, release)
    local uid, data = player.UserId, playerData[player.UserId]
    if not data then return end

    -- Data Sementara tidak pernah ditulis ke DataStore.
    if not data.IsTemporary then
        data.LastPlayed = os.time()
        local ok, err = pcall(function() dataStore:SetAsync(tostring(uid), data) end)
        if not ok then warn("[DM] save fail:", err) end
    end

    if release then
        local lock = sessionLocks[uid]
        if lock then releaseLock(uid, lock.LockId); sessionLocks[uid] = nil end
        playerData[uid] = nil
    end
end

return DataManager
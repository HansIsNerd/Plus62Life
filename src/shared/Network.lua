--!nonstrict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local Network = {}
local IS_SERVER = RunService:IsServer()
local FOLDER_NAME = "Remotes"

local REMOTE_EVENTS = {
    "StatChanged", "LogAdded", "PhaseChanged",
    "EventShow", "MiniGameStart", "MiniGameEnd",
    "GameStateChanged", "EndingTriggered", "Toast",
}
local REMOTE_FUNCTIONS = {
    "GetData", "NextWeek", "ApplyChoice", "SubmitMiniGame",
}

local events, functions = {}, {}

local function getFolder()
    local f = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
    if not f then
        f = Instance.new("Folder"); f.Name = FOLDER_NAME; f.Parent = ReplicatedStorage
    end
    return f
end

if IS_SERVER then
    local folder = getFolder()
    for _, name in ipairs(REMOTE_EVENTS) do
        local r = folder:FindFirstChild(name) or Instance.new("RemoteEvent")
        r.Name = name; r.Parent = folder; events[name] = r
    end
    for _, name in ipairs(REMOTE_FUNCTIONS) do
        local r = folder:FindFirstChild(name) or Instance.new("RemoteFunction")
        r.Name = name; r.Parent = folder; functions[name] = r
    end
else
    local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
    for _, name in ipairs(REMOTE_EVENTS)    do events[name]    = folder:WaitForChild(name) end
    for _, name in ipairs(REMOTE_FUNCTIONS) do functions[name] = folder:WaitForChild(name) end
end

function Network:FireClient(e, p, ...)  assert(events[e], e); events[e]:FireClient(p, ...) end
function Network:FireAllClients(e, ...) assert(events[e], e); events[e]:FireAllClients(...) end
function Network:OnClientEvent(e, cb)   assert(events[e], e); return events[e].OnClientEvent:Connect(cb) end
function Network:OnServerEvent(e, cb)   assert(events[e], e); return events[e].OnServerEvent:Connect(cb) end
function Network:FireServer(e, ...)     assert(events[e], e); events[e]:FireServer(...) end
function Network:InvokeServer(f, ...)   assert(functions[f], f); return functions[f]:InvokeServer(...) end
function Network:OnServerInvoke(f, cb)  assert(functions[f], f); functions[f].OnServerInvoke = cb end
function Network:OnClientInvoke(f, cb)  assert(functions[f], f); functions[f].OnClientInvoke = cb end

return Network
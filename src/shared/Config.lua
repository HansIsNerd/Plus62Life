--!strict
local Config = {}

Config.GameName = "Warga +62: Survival Life Sim"
Config.Version  = "0.1.0"

Config.WeeksPerYear  = 4
Config.Phases        = { "Senin-Kamis", "Jumat", "Sabtu", "Minggu" }
Config.PhaseDuration = 2

Config.Stats = {
    Cash       = { Min = -math.huge, Max = math.huge, Default = 0   },
    Health     = { Min = 0,          Max = 100,       Default = 100 },
    Stress     = { Min = 0,          Max = 100,       Default = 0   },
    Reputation = { Min = 0,          Max = 100,       Default = 50  },
    Debt       = { Min = 0,          Max = math.huge, Default = 0   },
}

Config.Colors = {
    Primary   = Color3.fromHex("34C759"),
    Danger    = Color3.fromHex("FF3B30"),
    Info      = Color3.fromHex("007AFF"),
    Warning   = Color3.fromHex("FF9500"),
    BgDark    = Color3.fromHex("1C1C1E"),
    BgLight   = Color3.fromHex("F2F2F7"),
    TextDark  = Color3.fromHex("000000"),
    TextLight = Color3.fromHex("FFFFFF"),
}

Config.DataStoreName    = "Warga62_PlayerData_v1"
Config.SessionLockName  = "Warga62_SessionLock"
Config.AutoSaveInterval = 300

Config.LifeStages = {
    { Name = "Bayi",    MinAge = 0,  MaxAge = 5   },
    { Name = "Anak",    MinAge = 6,  MaxAge = 18  },
    { Name = "Dewasa",  MinAge = 19, MaxAge = 24  },
    { Name = "Kerja",   MinAge = 25, MaxAge = 50  },
    { Name = "Pensiun", MinAge = 51, MaxAge = 100 },
}

return Config
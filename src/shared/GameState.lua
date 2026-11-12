--!strict
local GameState = {}

GameState.State = {
    IDLE       = "IDLE",
    WEEK_PHASE = "WEEK_PHASE",
    EVENT      = "EVENT",
    MINIGAME   = "MINIGAME",
    ENDING     = "ENDING",
}

return GameState
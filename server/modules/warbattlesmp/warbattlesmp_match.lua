
local nk            = require("nakama")
local utils         = require("utils")
local warbattle     = require("warbattlesmp")

local OP_CODE_MOVE = 1
local OP_CODE_STATE = 2

local M = {
}

local function broadcast_gamestate_to_recipient(dispatcher, gamestate, recipient)
    -- nk.logger_info("broadcast_gamestate")
    local message = tclean( {
        state = gamestate,
    } )
    local encoded_message = nk.json_encode(message)
    dispatcher.broadcast_message(OP_CODE_STATE, encoded_message, { recipient })
end

function M.match_init(context, setupstate)
    nk.logger_info("match_init")
    local gamestate = warbattle.creategame(setupstate.uid, setupstate.gamename)
    local tickrate = 2 -- per sec
    local label = setupstate.gamename
    return gamestate, tickrate, label
end

function M.match_join_attempt(context, dispatcher, tick, gamestate, presence, metadata)
    nk.logger_info("match_join_attempt")
    local acceptuser = tcount(gamestate.people) < 4
    if(acceptuser == true) then 
        gamestate = warbattle.updateperson(gamestate, presence)
        gamestate.init = warbattle.getgameinit(presence.user_id, gamestate.gamename)
    end
    return gamestate, acceptuser
end

function M.match_join(context, dispatcher, tick, gamestate, presences)
    nk.logger_info("match_join")
    return gamestate
end

function M.match_leave(context, dispatcher, tick, gamestate, presences)
    nk.logger_info("match_leave")
    -- end match if someone leaves
    return nil
end

function M.match_loop(context, dispatcher, tick, gamestate, messages)
    -- nk.logger_info("match_loop")
    gamestate.frame = gamestate.frame + 1
    gamestate.time = gamestate.frame * 0.5

    local newgamestate = warbattle.updategame( gamestate )
    for _, presence in ipairs(newgamestate.people) do
        broadcast_gamestate_to_recipient(dispatcher, newgamestate, presence)
    end

    return newgamestate
end

function M.match_signal(context, dispatcher, tick, state, data)
	
    return state, "signal received: "
end

function M.match_terminate(context, dispatcher, tick, gamestate, grace_seconds)
    nk.logger_info("match_terminate")
    local message = "Server shutting down in " .. grace_seconds .. " seconds"
    dispatcher.broadcast_message(2, message)
    return nil
end

return M

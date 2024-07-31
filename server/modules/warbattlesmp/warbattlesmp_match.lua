
local nk            = require("nakama")
local utils         = require("utils")
local warbattle     = require("warbattlesmp")

local OP_CODE_MOVE = 1
local OP_CODE_STATE = 2

local M = {
}

local function broadcast_gamestate_to_recipient(dispatcher, gamestate, recipient)
    nk.logger_info("broadcast_gamestate")
    local message = tclean( {
        state = gamestate,
    } )
    local encoded_message = nk.json_encode(message)
    dispatcher.broadcast_message(OP_CODE_STATE, encoded_message, { recipient })
end

function M.match_init(context, setupstate)
    nk.logger_info("match_init")
    M.gamestate = warbattle.creategame(setupstate.uid, setupstate.gamename)
    nk.localcache_put("warbattle", warbattle, 0)
    local tickrate = 1 -- per sec
    local label = M.gamestate.gamename
    return M.gamestate, tickrate, label
end

function M.match_join_attempt(context, dispatcher, tick, gamestate, presence, metadata)
    nk.logger_info("match_join_attempt")
    local acceptuser = tcount(gamestate.people) < 4
    return gamestate, acceptuser
end

function M.match_join(context, dispatcher, tick, gamestate, presences)
    nk.logger_info("match_join")
    gamestate.people = presences
    if tcount(presences) == 4 then
        -- broadcast_gamestate(dispatcher, gamestate)
    end
    return gamestate
end

function M.match_leave(context, dispatcher, tick, gamestate, presences)
    nk.logger_info("match_leave")
    -- end match if someone leaves
    return nil
end

function M.match_loop(context, dispatcher, tick, gamestate, messages)
    nk.logger_info("match_loop")
    local warbattle = nk.localcache_get("warbattle")
    gamestate.frame = gamestate.frame + 1
    gamestate.time = gamestate.frame

    local newgamestate = warbattle.updategame( gamestate )

    for _, presence in ipairs(gamestate.people) do
        -- warbattle.add_player(gamestate, presence)
        broadcast_gamestate_to_recipient(dispatcher, gamestate, presence)
    end

    -- Clear init after first 10 frames. New players will get sent an init sequence
    if( gamestate.frame > 10 and gamestate.init ) then 
        gamestate.init = nil 
    end

    if gamestate.rematch_countdown then
        gamestate.rematch_countdown = gamestate.rematch_countdown - 1
        if gamestate.rematch_countdown == 0 then
            gamestate = warbattle.creategame(gamestate.uid, gamestate.name)
        end
        -- broadcast_gamestate(dispatcher, gamestate)
    end

    return newgamestate or gamestate
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

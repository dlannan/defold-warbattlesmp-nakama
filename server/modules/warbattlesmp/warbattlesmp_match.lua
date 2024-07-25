
local warbattlesmp  = require("warbattlesmp_state")
local warbattles    = require("warbattlesmp")
local nk = require("nakama")

local OP_CODE_MOVE = 1
local OP_CODE_STATE = 2

local M = {}

local function tcount(t) 
	local count = 0
	if(t == nil) then return count end
	for k,v in pairs(t) do 
		count = count + 1
	end 
	return count
end

local function tclean(t)
    if type(t) == "table" then
        for k,v in pairs(t) do
            if(type(v) == "table") then 
                t[k] = tclean(v)
            elseif(type(v) == "function") then 
                t[k] = nil               
            end
        end
        return t
    end
end

local function pprint(t)
    if type(t) ~= "table" then
        nk.logger_info(tostring(t))
    else
        for k,v in pairs(t) do
            if(type(v) == "table") then 
                pprint(v)
            else 
                nk.logger_info(string.format("%s = %s", tostring(k), tostring(v)))
            end
        end
    end
end

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
    local gamestate = warbattlesmp.new_game(setupstate)
    local tickrate = 1 -- per sec
    local label = gamestate.gamename
    return gamestate, tickrate, label
end

function M.match_join_attempt(context, dispatcher, tick, gamestate, presence, metadata)
    nk.logger_info("match_join_attempt")
    local acceptuser = tcount(gamestate.people) < 4
    return gamestate, acceptuser
end

function M.match_join(context, dispatcher, tick, gamestate, presences)
    nk.logger_info("match_join")
    gamestate.people = presences
    if warbattlesmp.player_count(gamestate) == 4 then
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
    gamestate.frame = gamestate.frame + 1
    gamestate.time = gamestate.frame

    for _, message in ipairs(messages) do
        nk.logger_info(string.format("Received %s from %s", message.data, message.sender.username))
    end

    local newgamestate = warbattles.updategame( gamestate )

    for _, presence in ipairs(gamestate.people) do
        -- warbattlesmp.add_player(gamestate, presence)
        broadcast_gamestate_to_recipient(dispatcher, gamestate, presence)
    end

    -- Clear init after first 10 frames. New players will get sent an init sequence
    if( gamestate.frame > 10 and gamestate.init ) then 
        gamestate.init = nil 
    end

    if gamestate.rematch_countdown then
        gamestate.rematch_countdown = gamestate.rematch_countdown - 1
        if gamestate.rematch_countdown == 0 then
            gamestate = warbattlesmp.rematch(gamestate)
        end
        -- broadcast_gamestate(dispatcher, gamestate)
    end

    return newgamestate or gamestate
end

function M.match_signal(context, dispatcher, tick, state, data)
	return state, "signal received: " .. data
end

function M.match_terminate(context, dispatcher, tick, gamestate, grace_seconds)
    nk.logger_info("match_terminate")
    local message = "Server shutting down in " .. grace_seconds .. " seconds"
    dispatcher.broadcast_message(2, message)
    return nil
end

return M

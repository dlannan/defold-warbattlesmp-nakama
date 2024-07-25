local nk = require("nakama")

local warbattles = require("warbattlesmp")

local function tcount(t) 
	local count = 0
	if(t == nil) then return count end
	for k,v in pairs(t) do 
		count = count + 1
	end 
	return count
end

local function pprint(t)
    if type(t) ~= "table" then
        nk.logger_info(tostring(t))
    else
        for k,v in pairs(t) do
            nk.logger_info(string.format("%s = %s", tostring(k), tostring(v)))
        end
    end
end

local M = {}

local function create_state(state)
	pprint(state)
	return warbattles.creategame(state.uid, state.name)
end

function M.new_game(setupstate)
	return create_state(setupstate)
end

function M.rematch(state)
	assert(state)
	return create_state(state)
end

function M.add_player(state, player_id)
	assert(state)
	assert(player_id)
	pprint(state.players)
	return state
end

function M.player_count(state)
	assert(state)
	return tcount(state.players)
end

function M.player_move(state, row, column)
	assert(state)
	
	return state, true
end

function M.get_active_player(state)
	assert(state)
	return state.players[state.player_turn]
end

function M.get_other_player(state)
	assert(state)
	return state.players[(state.player_turn == 1) and 2 or 1]
end

function M.dump(state)
	-- for r=1,3 do
	-- 	local c1 = state.cells[r][1]
	-- 	local c2 = state.cells[r][2]
	-- 	local c3 = state.cells[r][3]
	-- 	print(("[%02d][%02d][%02d]"):format(c1, c2, c3))
	-- end
end

return M

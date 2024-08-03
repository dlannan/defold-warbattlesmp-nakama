
local nk                = require("nakama")
-- Main warbattles global lua state (not sure if this is valid, might need stoprage obj)
local utils             = require("utils")
local warbattle         = require("warbattlesmp")
local modulename        = "warbattlesmp_match"

local ERROR = {
    OK          = "ERROR_OK",
    BADDATA     = "ERROR_BAD_DATA",
}

-- Manually create a match with RPC call - this bypasses normal match making which isnt
--   needed for this demo
local function domatchcreate(context, payload)
    -- Only declare once?
    plog("Creating WarBattles match")
    local data = nk.json_decode(context.query_params.payload[1])
    local matchid = nk.match_create(modulename, data)
    return matchid
end

-- Send data directly to the warbattles state machine.
--   This way we dont have to 'wait' for data to coalesence and send back in match_loop (slow)
--   Once warbattles 'state' reaches a coalesence threshold, then broadcast to the other players
--   The aim of this is if there are many messages happening per match loop then they can be processed
--   fast enough to not need too much predicion. An alternate implementation (may do later) is
--   to include prediction in this call to warbattles and thus have more accurate collision and 
--   movement results (this would also require a more input device based message events)
local function sendmatchdata(context, payload)

    local data = nk.json_decode(context.query_params.payload[1])
    if(data) then 
        local match = nk.match_get(data.match_id)
        warbattle.processmessage(context.user_id, data.gamename, data)
    else
        return ERROR.BADDATA
    end
    return ERROR.OK
end

nk.register_rpc(domatchcreate, "DoMatchCreate")
nk.register_rpc(sendmatchdata, "SendMatchData")

-- Manually auth a device id (not sure if this works)
nk.authenticate_device("c1affd14799b725d623b54f15e79f8bc")
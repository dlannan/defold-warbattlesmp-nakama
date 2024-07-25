--[[
  Copyright 2020 The Defold Foundation Authors & Contributors

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

  http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
]]--

local nk = require("nakama")

local modulename = "warbattlesmp_match"


local function pprint(t)
    if type(t) ~= "table" then
        nk.logger_info(tostring(t))
    else
        for k,v in pairs(t) do
            nk.logger_info(string.format("%s = %s", tostring(k), tostring(v)))
        end
    end
end

local function log(fmt, ...)
    nk.logger_info(string.format(fmt, ...))
end

-- callback when two players have been matched
-- create a match with match logic from tictactoe_match.lua
-- return match id
local function domatchcreate(context, payload)
    log("Creating WarBattles match")
    local data = nk.json_decode(context.query_params.payload[1])

    if(data) then pprint(data) end
    local matchid = nk.match_create(modulename, data)
    return matchid
end

local function authcustom(context, inData)
    log("WarBattles Custom Auth")

    local token = inData.GetAccount().GetId()
    inData.Account.Id = "1234567"

    return inData, nil
end

nk.run_once(function(ctx)
    local now = os.time()
    log("Backend loaded at %d", now)
    -- nk.register_rt_before(authcustom, "AuthenticateCustom")
end)

nk.register_rpc(domatchcreate, "DoMatchCreate")

-- Manually auth a device id (not sure if this works)
nk.authenticate_device("c1affd14799b725d623b54f15e79f8bc")
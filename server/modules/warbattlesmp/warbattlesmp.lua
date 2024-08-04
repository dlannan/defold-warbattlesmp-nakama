
---------------------------------------------------------------------------------
-- A name for the game. 
local modulename        = "WarBattlesMP"
local utils             = require("utils")

local nk                = require("nakama")

OSVehicle               = require("opensteer.os-simplevehicle")
OSPathway               = require("opensteer.os-pathway")
Vec3                    = require("opensteer.os-vec")

-- General game operation:
--    Drop in play. Can join any game any time. 
--    Once joined, increase amount of tanks to match players. 
--    Update character positions and rockets
--    Run tanks AI
--    Check if tanks are exploded - respawn if needed
--    Update Player list and player scores
--    If player exit, then reduce AI tanks (just drop a respawn)
--    If no players for 5 minutes, drop game

---------------------------------------------------------------------------------
-- Each entry in this table creates a sqltable for use in this module
local SQLITE_TABLES     = {
    ["gamedata"]      = { create = "desc TEXT, data TEXT" },
}

local allWSServers      = {}
allWSServersCount       = 0

-- ---------------------------------------------------------------------------
-- User defined events - these are handled in your module
local USER_EVENT 	    = {
	REQUEST_GAME 	    = 1,
	POLL 			    = 2,

	REQUEST_READY	    = 10,
	REQUEST_START 	    = 20,
	REQUEST_WAITING     = 30,
	REQUEST_ROUND 	    = 40,
    REQUEST_PEOPLE 	    = 41,

	-- Some War Battle Specific Events 
	PLAYER_STATE 	    = 50, 		-- Generic DO EVERYTHING state 

	-- Smaller simple states (should use this TODO)
	PLAYER_SHOOT	    = 60,		-- Player lauched a rocket 
	PLAYER_HIT		    = 70,		-- Client thinks rocket hit something - server check
	PLAYER_MOVE 	    = 80,		-- Movement has occurred update server

    TANK_SPAWN          = 100,
    TANK_KILL           = 110,
    TANK_MOVE           = 120,
    TANK_SHOOT          = 130,
}

---------------------------------------------------------------------------------
-- Required properties are: 
--   name, and sqltables if you want sql persistent data
local warbattlempgame        = {
    -- You must set this. Or the user will be logged out with a single update
    USER_TIMEOUT    = 120,      

    name            = modulename,    
    sqltables       = SQLITE_TABLES,
    max_games       = 50,
    data            = { games = {} },
}

---------------------------------------------------------------------------------
-- Dont put this in module data or it will be shared!
local gamedata = {

    max_tanks       = 20,

    -- List of paths used by tanks (common to all games)
    tank_paths      = {
        { 230.08,578.55,328.37,620.25,328.37,620.25,
        328.37,620.25,432.61,606.85,432.61,606.85,
        432.61,606.85,495.16,557.70,495.16,557.70,
        495.16,557.70,578.55,461.65,578.55,461.65,
        578.55,461.65,664.93,425.17,666.41,425.17,
        667.90,425.17,785.55,398.36,785.55,398.36,
        785.55,398.36,815.33,327.62,815.33,326.13,
        815.33,324.64,787.04,236.04,787.04,236.04,
        787.04,236.04,683.54,233.80,683.54,233.80,
        683.54,233.80,663.44,282.95,663.44,282.95,
        663.44,282.95,616.53,345.49,616.53,345.49,
        616.53,345.49,535.37,338.05,535.37,338.05,
        535.37,338.05,397.62,294.86,397.62,294.86,
        397.62,294.86,260.61,290.39,260.61,290.39,
        260.61,290.39,202.53,324.64,202.53,324.64,
        202.53,324.64,137.75,387.19,137.75,387.19,
        137.75,387.19,113.18,436.33,113.18,436.33,
        113.18,436.33,184.66,495.90,184.66,495.90,
        184.66,495.90,221.15,533.88,219.66,533.88 },

        { 138.50,565.15,242.74,562.92,242.74,562.92,
        242.74,562.92,401.34,551.75,401.34,551.75,
        401.34,551.75,431.12,516.75,431.12,516.75,
        431.12,516.75,265.08,524.94,265.08,524.94,
        265.08,524.94,219.66,505.58,219.66,505.58,
        219.66,505.58,116.16,466.86,116.16,466.86,
        116.16,466.86,68.50,491.43,68.50,491.43,
        68.50,491.43,102.75,539.83,102.75,539.83},

        { 331.35,352.19,295.61,206.25,295.61,206.25,
        295.61,206.25,382.72,143.71,382.72,143.71,
        382.72,143.71,459.42,214.44,459.42,214.44,
        459.42,214.44,478.78,364.11,478.03,365.60,
        477.29,367.09,424.42,519.73,424.42,519.73,
        424.42,519.73,424.42,609.83,424.42,609.83,
        424.42,609.83,346.24,648.54,346.24,648.54,
        346.24,648.54,266.57,583.76,266.57,583.76,
        266.57,583.76,326.13,494.41,326.13,494.41,
        326.13,494.41,334.32,404.32,334.32,404.32 },

        { 635.14,355.17,707.37,333.58,707.37,333.58,
        707.37,333.58,766.19,286.67,766.19,286.67,
        766.19,286.67,720.77,174.98,720.77,174.98,
        720.77,174.98,644.08,124.35,644.08,124.35,
        644.08,124.35,541.32,131.05,541.32,131.05,
        541.32,131.05,565.15,166.79,565.15,166.79,
        565.15,166.79,643.33,210.72,644.08,211.47,
        644.82,212.21,662.69,271.78,662.69,271.78,
        662.69,271.78,653.76,311.99,653.76,311.99 },

        { 556.21,642.59,641.10,641.84,641.10,641.84,
        641.10,641.84,761.72,641.84,761.72,641.84,
        761.72,641.84,807.14,615.04,807.14,615.04,
        807.14,615.04,775.87,553.24,775.87,553.24,
        775.87,553.24,737.15,527.92,737.15,527.92,
        737.15,527.92,573.34,528.66,573.34,528.66,
        573.34,528.66,518.98,533.13,519.73,533.88,
        520.47,534.62,502.60,580.04,502.60,580.04,
        502.60,580.04,519.73,619.51,520.47,619.51 },

        { 207.74,357.41,186.15,218.91,186.15,218.91,
        186.15,218.91,281.46,99.03,281.46,99.03,
        281.46,99.03,459.42,154.88,459.42,154.88,
        459.42,154.88,475.80,307.52,475.80,307.52,
        475.80,307.52,601.63,412.51,601.63,412.51,
        601.63,412.51,744.60,469.10,744.60,469.10,
        744.60,469.10,822.78,639.61,822.78,639.61,
        822.78,639.61,707.37,731.19,707.37,731.19,
        707.37,731.19,539.09,675.35,539.09,675.35,
        539.09,675.35,552.49,513.77,552.49,513.77,
        552.49,513.77,423.68,437.08,423.68,437.08,
        423.68,437.08,280.71,540.58,280.71,540.58,
        280.71,540.58,172.00,492.92,172.00,492.92,
        172.00,492.92,97.54,428.14,97.54,428.14 },
    },
    tank_ospaths = {},
}

---------------------------------------------------------------------------------
-- Build poly paths for the tanks

for k,v in ipairs(gamedata.tank_paths) do 

    -- convert points to OSVec3 
    local points = {}
    local radius = 1

    local ptcount = table.getn(v) / 2 
    for i=0, ptcount - 1 do  
        local pt = Vec3Set(v[i * 2 + 1 ], 0, v[i * 2 + 2])
        points[i] = pt
    end

    local polypath = OSPathway()
    polypath.initialize( ptcount, points, radius, true )
    gamedata.tank_ospaths[k] = polypath
end

---------------------------------------------------------------------------------

local Tank = function( gameobj ) 

    local self = {}
    -- // constructor
    self.mover = OSVehicle()

    gameobj.tank_count = gameobj.tank_count + 1
    self.m_MyID = gameobj.tank_count

    -- // reset state
    self.reset = function() 
        self.mover.reset() -- // reset the vehicle 
        self.mover.setSpeed (0.0)         -- // speed along Forward direction.
        self.mover.setMaxForce (20.7)      -- // steering force is clipped to this magnitude
        self.mover.setMaxSpeed (10)         -- // velocity is clipped to this magnitude
        self.mover.setRadius(1.25)

        -- // Place at start of a path 
        self.allpaths = gamedata.tank_paths
        self.path = math.random(1, table.getn(self.allpaths))
        self.ospath = gamedata.tank_ospaths[self.path]
        self.pathlen = self.ospath.getTotalPathLength()

        self.dist = math.random(self.pathlen)

        local pos = self.ospath.mapPathDistanceToPoint(self.dist)
        self.mover.setPosition( Vec3Set(pos.x, 0, pos.y ) )
    end

    -- // per frame simulation update
    -- // (parameter names commented out to prevent compiler warning from "-W")
    self.update = function( elapsedTime) 


        self.dist = self.dist + elapsedTime * self.mover.speed()
        local pos = self.ospath.mapPathDistanceToPoint(self.dist)

        local seekTarget = self.mover.xxxsteerForSeek(pos)
        self.mover.applySteeringForce (seekTarget.mult(2.0), elapsedTime)
    end

    self.reset()
    return self
end

---------------------------------------------------------------------------------
-- Create some tanks that follow some paths.
local function createTanks( gameobj )
    local tanks = {}
    local tanksinit = {}
    for i=1, gamedata.max_tanks do 
        local gotank = Tank(gameobj)    
        table.insert( tanks, gotank )
        table.insert( tanksinit, { id = gotank.m_MyID, start = gotank.dist, path = gotank.path } )
    end 
    gameobj.tanks = tanks
    gameobj.init = tanksinit
end

---------------------------------------------------------------------------------
-- Update the tanks
local function updateTanks( gameobj, dt )
    for k,tank in ipairs(gameobj.tanks) do 
        tank.update(dt)
    end 
end

---------------------------------------------------------------------------------
-- Reset the tanks
local function resetTanks( gameobj )
    for k,tank in ipairs(gameobj.tanks) do 
        tank.reset()
    end 
end

---------------------------------------------------------------------------------
-- Gets a cleaned up gameobject (less data)
local function getGameObject(gameobj)

    local slimobj = {
        name        = gameobj.name,
        gamename    = gameobj.gamename, 
        maxsize     = gameobj.maxsize,
        people      = gameobj.people,
        owner       = gameobj.owner, 
        private     = gameobj.private, 
        state       = gameobj.state or {},
        frame       = gameobj.frame,
        time        = gameobj.time,

        ws_port     = gameobj.ws_port,
    }
    return slimobj
end 

---------------------------------------------------------------------------------
-- Run an individual game step. 
--   The game operations occur here. Usually:
--     - Check inputs/changes
--     - Apply to game state
--     - Output state changes
--     - Update game sync 
-- 
---------------------------------------------------------------------------------
-- Check state 
local function checkState( newgamestate )

    -- Push newstate into current game
    local game = nk.localcache_get("warbattle_"..newgamestate.gamename)
    for k,v in pairs(newgamestate) do
        game[k] = v
    end

    if(game.state) then 
        for k,v in ipairs(game.state) do

            -- kill state if lifetime is old
            if(v and game.frame > v.lt) then 
                table.remove(game.state, i)
            end         
        end 
        -- Allows client to sync to the module frame
        game.state.frame = game.frame
    end 

    -- Write back any changes to the cache. This is shitty, would be better to use a lua table 
    --   Even a global one would be nicer.
    nk.localcache_put("warbattle_"..game.gamename, game, 0)
    return game 
end

---------------------------------------------------------------------------------
-- Gets the init data for a game (when a player joins)
warbattlempgame.getgameinit = function(uid, name)
    
    if(name == nil) then return nil end
    local game = nk.localcache_get("warbattle_"..name)
    if(game == nil) then return nil end 
    local temp = getGameObject(game)

    -- Tell all players there is a new player
    for k, person in pairs(game.people) do
        if(person.user_id == uid) then temp.init = game.init else temp.init = nil end
        nk.notification_send(person.user_id, "PLAYER_JOINED", temp, USER_EVENT.REQUEST_GAME, nil, true)
    end
    return game.init
end

---------------------------------------------------------------------------------
-- Gets the init data for a game (when a player joins)
warbattlempgame.getgame = function(name)
    
    local game =  nk.localcache_get("warbattle_"..name)
    if(game == nil) then return nil end 
    return game
end


---------------------------------------------------------------------------------
-- When number of people change notify all clients 

warbattlempgame.updateperson = function(game, newperson)

    -- get this game assuming you stored it :) and then do something 
    local game =  warbattlempgame.getgame(game.gamename) 
    if(game == nil) then return nil end 

    if(game.people == nil) then game.people = {} end
    table.insert(game.people, newperson)
    nk.localcache_put("warbattle_"..game.gamename, game, 0)
    return game
end

---------------------------------------------------------------------------------
--    TODO: There may be a need to run this in a seperate Lua Env.
--   dt is in milliseconds
local function runGameStep( game, frame, dt )

    game.frame = frame

    -- Do anything with states - collision, scoring.. etc
    --updateTanks(game, dt)
 
    -- Have to doa copy of state may be changed while we are sending to clients.
    local laststate = game.state
    game.state = {}

    local msg = { event = "REQUEST_ROUND", data = laststate, time = game.time, frame = game.frame }
    local rrdata = SFolk.dumps(msg)
    local ws_server = allWSServers[game.gamename]
    if(ws_server) then 
        for i,client in ipairs(ws_server.clients) do
            if(client) then 
                client:send(rrdata)
            end
        end
    end

    -- checkState(game)
end 

---------------------------------------------------------------------------------
-- Create a new game in this module. 
--    Each game can be tailored as needed.
warbattlempgame.creategame   = function( uid, name )

    local gameobj = {
        name        = modulename,
        gamename    = name, 
        sqlname     = "TblGame"..modulename,
        maxsize     = 4,
        people      = {},
        round       = {},
        owner       = uid, 
        private     = true, 
        state       = {},

        frame       = 0,
        time        = 0.0,
        tank_count  = 0,
    }

    createTanks( gameobj )

    nk.localcache_put("warbattle_"..name, gameobj, 0)
    return getGameObject(gameobj)
end 


---------------------------------------------------------------------------------
-- Process incoming messages from clients
--     Check for consistency (for bullets, collisions and explosions)
--     Send moves out to alll (this will happen in update)
warbattlempgame.processmessage   =  function( uid, name, message )

    -- get this game assuming you stored it :) and then do something 
    local game =  warbattlempgame.getgame(name) 
    if(game == nil) then return nil end 

    local data =  message
    local subject = nil

    if(data.event == USER_EVENT.PLAYER_MOVE) then 

        subject = "PLAYER_MOVE"
    elseif (data.event == USER_EVENT.PLAYER_HIT) then 

        subject = "PLAYER_HIT"
    elseif (data.event == USER_EVENT.PLAYER_SHOOT) then 

        subject = "PLAYER_SHOOT"
    end

    if(subject) then 
        -- Post this to all players
        for _, presence in ipairs(game.people) do
            if(uid ~= presence.user_id) then  -- Dont send stuff to self
                nk.notification_send(presence.user_id, subject, data, data.event, nil, true)
            end
        end
    end
end

---------------------------------------------------------------------------------
-- Update provides feedback data to an update request from a game client. 
warbattlempgame.updategame   =  function( gamestate )

    -- get this game assuming you stored it :) and then do something 
    local game =  warbattlempgame.getgame(gamestate.gamename)
    if(game == nil) then return nil end 

    local result = nil
    -- -- Cleanup states in case there are old ones 
    result = checkState( gamestate )

    -- Return some json to players for updates 
    return getGameObject(result)
end 


---------------------------------------------------------------------------------
-- Called when a user joins a game. 
warbattlempgame.joingame   =  function( uid, name )

    -- get this game assuming you stored it :) and then do something 
    local game = nk.localcache_get("warbattle_"..name)
    if(game == nil) then return nil end 
end

---------------------------------------------------------------------------------
-- Called when a user leaves a game 
warbattlempgame.leavegame   =  function( uid, name )
    
    -- get this game assuming you stored it :) and then do something 
    local game = nk.localcache_get("warbattle_"..name)
    if(game == nil) then return nil end 
end

---------------------------------------------------------------------------------
return warbattlempgame
---------------------------------------------------------------------------------

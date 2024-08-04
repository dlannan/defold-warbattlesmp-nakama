local tinsert 			= table.insert
local tremove 			= table.remove

local bser 				= require "lua.binser"

local nakama 			= require "nakama.nakama"
local realtime 			= require "nakama.socket"
local log 				= require "nakama.util.log"
local defold 			= require "nakama.engine.defold"
local json 				= require "nakama.util.json"
local utils  			= require "lua.utils"
local chance 			= require("lua.chance")	


-- Use a single device id value (easier auth)
local ENABLE_FIXED_DEVICE		= nil

-- Some general settings. This is game specific.
local MAX_LOGIN_ATTEMPTS		= 10
local MAX_CONNECT_ATTEMPTS 		= 10 

local MODULE_NAME 				= "warbattlesmp_match"
local HOST 						= "nakama.kakutai.com"
local PORT 						= 7350

local RPC_DOMATCHCREATE 		= "DoMatchCreate"
local RPC_DOMATCHJOIN	 		= "DoMatchJoin"
local RPC_SENDMATCHDATA 		= "SendMatchData"

-- ---------------------------------------------------------------------------
-- Game level states.
--   These track where you are in the login and running process
local GAME		 	= {
	LOGGING_IN 		= 1,
	LOGIN_OK		= 2,
	LOGIN_FAIL		= 3,

	SETUP			= 10,

	GAME_JOINING	= 20, 

	EXIT 			= 90,
}

-- ---------------------------------------------------------------------------
-- User defined events - these are handled in your module
local USER_EVENT 	= {
	REQUEST_GAME 	= 1,
	POLL 			= 2,

	REQUEST_READY	= 10,
	REQUEST_START 	= 20,
	REQUEST_WAITING = 30,
	REQUEST_ROUND 	= 40,
	REQUEST_PEOPLE 	= 41,

	-- Some War Battle Specific Events 
	PLAYER_STATE 	= 50, 		-- Generic DO EVERYTHING state 

	-- Smaller simple states (should use this TODO)
	PLAYER_SHOOT	= 60,		-- Player lauched a rocket 
	PLAYER_HIT		= 70,		-- Client thinks rocket hit something - server check
	PLAYER_MOVE 	= 80,		-- Movement has occurred update server
}

-- ---------------------------------------------------------------------------
local function resetclient(self)
	self.device_id = url.uuid()
end 

-- ---------------------------------------------------------------------------

local function genname(long)
	long = long or 9
	local m,c = math.random,("").char 
	local name = ((" "):rep(long):gsub(".",function()return c(("aeiouy"):byte(m(1,6)))end):gsub(".-",function()return c(m(97,122))end))
	return name
end

-- ---------------------------------------------------------------------------
-- authentication using device id
local function device_login(self)

	self.player_name = self.player_name or chance:name()
	self.client.uuid = self.client.uuid or defold.uuid(ENABLE_FIXED_DEVICE)
	-- login using the token and create an account if the user
	-- doesn't already exist
	local auth = nakama.authenticate_device(self.client, self.client.uuid, nil, true, self.player_name)
	if auth and auth.token then
		-- store the token and use it when communicating with the server
		nakama.set_bearer_token(self.client, auth.token)
		return true, auth
	end
	log("Unable to login")
	return false, auth
end

-- ---------------------------------------------------------------------------
-- Update match player name
local function setplayername( self, newname, callback )

	nakama.sync(function()
		nakama.get_account(self.client, function(result)
			-- Save user info for future logout and such
			if result and result.error then 
				pprint(result)
			else
				nakama.update_account(self.client, result.user.avatar_url or nil, newname, result.user.lang_tag or nil, 
						result.user.location or nil, result.user.timezone or nil, newname, function(msg)
					callback(msg, result)
				end)
			end
		end)
	end)
end	

-- ---------------------------------------------------------------------------
-- join a match (provided by the matchmaker)
local function join_match(self, match_id, token, match_callback)
	self.match = nil
	log("Sending match_join message")

	nakama.sync(function()
		
		local joindata = json.encode({ label = match_id, username = self.player_name, user_id = self.player_uid })
		pprint(joindata)
		local resp = nakama.rpc_func2(self.client, RPC_DOMATCHJOIN, joindata )

		nakama.sync(function()
			if resp and resp.payload == "" then

				local payload = json.encode({ gamename = self.gamename, uid = self.player_name })
				local resp = nakama.rpc_func2(self.client, RPC_DOMATCHCREATE, payload )

				realtime.match_join(self.socket, resp.payload, nil, nil, function(data)				
					self.match = data
					self.match.owner = self.player_uid
					match_callback(true, self.match)
				end)
			else
				realtime.match_join(self.socket, resp.payload, nil, nil, function(data)				
					self.match = data
					self.match.owner = nil
					match_callback(true, self.match)
				end)
			end
		end)
	end)
end

-- ---------------------------------------------------------------------------
-- leave a match
local function leave_match(self, match_id, callback)
	nakama.sync(function()
		log("Sending match_leave message")
		if(self.socket) then 
			local result = realtime.match_leave(self.socket, match_id, function(success)

				pprint(match_id)
				pprint(success)
				pprint(err)
				callback()
			end)
		end
	end)
end

-- ---------------------------------------------------------------------------
-- This is quite slow, only need a small portion of this. Example only.
local function make_requestgamestate(game_name, device_id) 

	-- User submission data must be in this format - will be checked
	local userdata = {

		state       = nil,   
		uid         = device_id,
		name        = game_name,
		round       = 0,
		timestamp   = os.time(),

		event       = USER_EVENT.REQUEST_GAME,
		json        = "",
	}
	return userdata
end 

-- ---------------------------------------------------------------------------
-- A normal updategame does a "request_round" event with no other data sent
local function updategame(self, callback) 

	if(self.game == nil) then return end 
end 

-- ---------------------------------------------------------------------------
-- send move as match data
local function send_player_move(match_id, row, col)
	nakama.sync(function()
		local data = json.encode({
			row = row,
			col = col,
		})
		log("Sending match_data message")
		local result = realtime.match_data_send(socket, match_id, 1, data)
		if result.error then
			log(result.error.message)
			-- pprint(result)
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Send data to the main game loop
--  	update state - player move, player shoot, and player exit

local function send_data(self, data)

	nakama.sync(function()
		local payload = json.encode(data)
		local resp = nakama.rpc_func2(self.client, RPC_SENDMATCHDATA, payload )
		if resp and resp.error then
			print(resp.error.message)
			-- pprint(resp)
		end
	end)
end

-- ---------------------------------------------------------------------------
-- handle received match data
-- decode it and pass it on to the game
local function handle_match_notification(self, notifications)

	pprint(notifications)
	for k, v in pairs(notifications.notifications.notifications) do 
		local content = json.decode(v.content)
		-- If this is an init call, then update game data!!!
		if(v.subject == "PLAYER_JOINED" and content.init) then 
			self.game = content 
		elseif(v.subject == "PLAYER_MOVE" and content) then 

		elseif(v.subject == "PLAYER_HIT" and content) then 

		elseif(v.subject == "PLAYER_MOVE" and content) then 

		end
	end
end

-- ---------------------------------------------------------------------------
-- handle received match data
-- decode it and pass it on to the game
local function handle_match_data(self, match_data)
	local data = json.decode(match_data.data)
	local op_code = tonumber(match_data.op_code)
		
	if op_code == 2 then
		self.game = data.state		
		-- pprint(data.state)
	else
		log(("Unknown opcode %d"):format(op_code))
	end
end

-- ---------------------------------------------------------------------------
-- handle when a player leaves the match
-- pass this on to the game
local function handle_match_presence(self, match_presence_event, message)
	
	if match_presence_event.leaves and #match_presence_event.leaves > 0 then
		--warbattles.opponent_left()
	end

	if match_presence_event.joins then 
		-- warbattles.join_match( function(success, message) 			
		--	pprint(success, message)
		--_Gend)
	end
end


-- ---------------------------------------------------------------------------
-- User defined callbacks
--    Defaults are provided

local callbacks 	= {
	match_notification 	= handle_match_notification,
	match_presence 		= handle_match_presence,
	match_data 			= handle_match_data,
}


-- ---------------------------------------------------------------------------
-- login to Nakama
-- setup listeners
-- * socket events from Nakama
-- * events from the game
local function login(self, callback)

	-- enable logging
	--log.print()
	
	-- create server config
	-- we read server url, port and server key from the game.project file
	local config = {}
	config.host = sys.get_config_string("nakama.host", HOST)
	config.port = sys.get_config_number("nakama.port", PORT)
	config.use_ssl = (config.port == 443)
	config.username = sys.get_config_string("nakama.server_key", "defaultkey")
	config.password = ""
	config.engine = defold

	self.client = self.client or nakama.create_client(config)

	nakama.sync(function()
		-- Start by doing a device login (the login will be tied
		-- not to a specific user but to the device the game is
		-- running on)
		if(self.auth == nil) then 
			local ok, auth = device_login(self)
			if not ok then
				callback(false, "Unable to login")
				return
			end
			-- the logged in account
			self.auth = auth
		end
		
		-- Next we create a socket connection as well
		-- we use the socket connetion to exchange messages
		-- with the matchmaker and match
		self.socket = self.socket or nakama.create_socket(self.client)

		local ok, err = realtime.connect(self.socket)
		if not ok then
			log("Unable to connect: ", err)
			callback(false, "Unable to create socket connection")
			return
		end		

		-- Called by Nakama when a player has left (or joined) the
		-- current match.
		-- We notify the game that the opponent has left.
		realtime.on_match_presence_event(self.socket, function(message)
			log("nakama.on_matchpresence")
			callbacks.match_presence(self, message.match_presence_event, message)
		end)

		-- Called by Nakama when the game state has changed.
		-- We parse the data and send it to the game.
		realtime.on_match_data(self.socket, function(message)
			log("nakama.on_matchdata")
			callbacks.match_data(self, message.match_data)
		end)

		realtime.on_notifications(self.socket, function(message)
			log("warbattles.on_notification")
			callbacks.match_notification(self, message)
		end)

		-- Normally in xoxo nakama joins are using matchmaker. Because we have a 
		-- match name, this is not needed. We join directly to the match.
		-- warbattles.on_join_match(function(fn_on_join)
		-- 	log("warbattles.on_join_match")
		-- end)

		-- Called by the game when the player pressed the Leave button
		-- when a game is finished (instead of waiting for the next match).
		-- We send a match leave message to Nakama. Fire and forget.
		-- warbattles.on_leave_match(function()
		-- 	log("warbattles.on_leave_match")
		-- 	leave_match(match.match_id)
		-- end)

		-- Called by the game when the player is trying to make a move.
		-- We send a match data message to Nakama.
		-- warbattles.on_send_player_move(function(row, col)
		-- 	log("warbattles.on_send_player_move")
		-- 	send_player_move(match.match_id, row, col)
		-- end)

		callback(true)
	end)
end

-- ---------------------------------------------------------------------------

local function logout( self )

	nakama.sync(function()
		if(self.client) then 
			nakama.session_logout(self.client)
			self.client = nil
			self.auth = nil 
			self.account = nil
			self.socket = nil 
		end
	end)
end


-- ---------------------------------------------------------------------------
return {
	-- setup 			= setup_swampy,
	login 			= login,
	logout 			= logout,
	-- connect 		= connect,
	
	resetclient		= resetclient,
	setplayername 	= setplayername,

	join_match		= join_match,
	leave_match		= leave_match,

	send_data		= send_data,
	update_game 	= update_game,
	callbacks		= callbacks,
	
	EVENT 			= USER_EVENT,
}

-- ---------------------------------------------------------------------------
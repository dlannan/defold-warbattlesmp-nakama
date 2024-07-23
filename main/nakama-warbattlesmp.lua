local tinsert 	= table.insert
local tremove 	= table.remove

local bser 		= require "lua.binser"

local warbattles = require "main.warbattles"
local nakama = require "nakama.nakama"
local realtime = require "nakama.socket"
local log = require "nakama.util.log"
local defold = require "nakama.engine.defold"
local json = require "nakama.util.json"

-- Some general settings. This is game specific.
local MAX_LOGIN_ATTEMPTS		= 10
local MAX_CONNECT_ATTEMPTS 		= 10 

local HOST 						= "swampy.kakutai.com"
local PORT 						= 7350

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

local function websocket_callback(self, conn, data)
	if data.event == websocket.EVENT_DISCONNECTED then
		pprint("Disconnected: " .. tostring(conn))
		self.ws_connect = nil
	elseif data.event == websocket.EVENT_CONNECTED then
		pprint("Connected: " .. tostring(conn))
	elseif data.event == websocket.EVENT_ERROR then
		pprint("Error: '" .. data.message .. "'")
	elseif data.event == websocket.EVENT_MESSAGE then
		pprint("Receiving: '" .. tostring(data.message) .. "'")
	end
end

 ---------------------------------------------------------------------------
-- --  Realtime games should use sockets (UDP ideally)

-- function websocket_open(self, callback)

-- 	callback = callback or websocket_callback
-- 	self.url = "wss://"..HOST..":"..self.game.ws_port
-- 	local params = {
-- 		timeout = 3000,
-- 	}
-- 	--params.headers = "Sec-WebSocket-Protocol: chat\r\n"
-- 	--params.headers = params.headers.."Origin: mydomain.com\r\n"

-- 	self.ws_connect = websocket.connect(self.url, params, callback)
-- end

-- ---------------------------------------------------------------------------
-- --  Send data to the server from client (usually movement and keypresses)
-- function websocket_send(self, eventmsg, callback)

-- 	if(self.ws_connect == nil) then return nil end 
-- 	--local eventmsg = bser.serialize(eventtbl)
-- 	websocket.send(self.ws_connect, eventmsg)
-- end

-- -- ---------------------------------------------------------------------------

-- function websocket_close(self)
-- 	if self.ws_connect ~= nil then
-- 		websocket.disconnect(self.ws_connect)
-- 	end
-- end

-- ---------------------------------------------------------------------------
-- Check connection when calling swampy funcs

-- local function check_connect(self)

-- 	local ok = nil
-- 	local resp = { status = "ERROR" } 
-- 	if(self.swp_account == nil) then  resp.status = "Connect Error: No valid swampy account."; return ok, resp end

-- 	if(self.swp_client.state == nil) then resp.status = "Connect Error: failed to connect."; return ok, resp end
-- 	if(self.client_id == nil) then  resp.status = "Connect Error: No Client Id."; return ok, resp end
-- 	if(self.user_id == nil) then  resp.status = "Connect Error: No User Id."; return ok, resp end 
-- 	if(self.swp_account == nil) then  resp.status = "Connect Error: No valid swampy account."; return ok, resp end
-- 	ok = true 
-- 	-- Handle other connect issues here
-- 	return ok, resp
-- end

-- ---------------------------------------------------------------------------

local function genname(long)
	long = long or 9
	local m,c = math.random,("").char 
	local name = ((" "):rep(long):gsub(".",function()return c(("aeiouy"):byte(m(1,6)))end):gsub(".-",function()return c(m(97,122))end))
	return name
end

-- -- ---------------------------------------------------------------------------
-- -- Setup server 
-- local function setup_swampy(self, modulename, uid)

-- 	swampy.setmodulename(modulename) 

-- 	-- The Nakama server configuration
-- 	local config = {}

-- 	config.host 		= HOST
-- 	config.port 		= 443
-- 	config.use_ssl 		= true 
-- 	config.api_token 	= "j3mHKlgGZ4" 

-- 	self.login_attempts	= 0
-- 	self.gamestate 		= 0

-- 	self.user_id		= uid
-- 	self.device_id		= genname(16)

-- 	self.swp_client 	= swampy.create_client(config)
-- 	-- pprint(self.swp_client)
-- end

-- ---------------------------------------------------------------------------
-- authentication using device id
local function device_login(client)
	-- login using the token and create an account if the user
	-- doesn't already exist
	local result = nakama.authenticate_device(client, defold.uuid(), nil, true)
	if result.token then
		-- store the token and use it when communicating with the server
		nakama.set_bearer_token(client, result.token)
		return true
	end
	log("Unable to login")
	return false
end

-- ---------------------------------------------------------------------------
-- Update match player name
local function updateplayername( self, match_data )

	for k,user in pairs(self.client_party.people) do 
		if(user.user_id == match_data.presence.user_id) then 
			local playerdata = json.decode(match_data.data)
			user.player_name = playerdata.player_name
		end
	end
end	

-- -- ---------------------------------------------------------------------------
-- local function connect(self, callback)

-- 	-- The connect process for the time beiing is to enable an account with user info 
-- 	--  attached to the device the user has and the user generated token they are connecting with.
-- 	self.swp_conn_attempts = (self.swp_conn_attempts or 0) + 1
-- 	if(self.swp_conn_attempts > MAX_CONNECT_ATTEMPTS) then callback({ status = "Connect Error: Exceeded connect attempts." }); return end

-- 	self.client_id 		= nil
-- 	self.user_id 		= nil
-- 	self.swp_account 	= nil

-- 	if(self.swp_client.state ~= "CONNECTING") then 
-- 		self.swp_client.state = "CONNECTING"
-- 		swampy.connect( self.swp_client, self.player_name, self.device_id, function(rdata)

-- 			if(rdata.status == "OK") then 
-- 				self.swp_account = rdata.data
-- 				-- Not sure this is needed anymore (nakama legacy)
-- 				self.client_id = self.swp_account.username 
-- 				self.user_id = self.swp_account.uid

-- 				print("Connected ok.")
-- 				self.swp_client.state = "CONNECTED"
-- 			else 
-- 				print("Connect failed.")
-- 				self.swp_client.state = nil
-- 			end
-- 			callback(rdata.status)
-- 		end)
-- 	end
-- end

-- join a match (provided by the matchmaker)
local function join_match(self, match_id, token, match_callback)
	local match = nil
	log("Sending match_join message")
	local metadata = { some = "1" }

	local resp = realtime.match_join(self.socket, match_id, nil, metadata)
	pprint(resp)
	if resp.match then
		pprint(resp)
		match = resp.match
		match_callback(true)
	elseif resp.error then
		log("[ERROR]"..resp.error.message)
		pprint("[ERROR]",resp)
		match = nil
	end			

	log("match_join done...")
	pprint(resp)

	-- Failed to join then make a game!
	if(resp.error) then 
		log("creating match: "..self.gamename)
		local match_data = realtime.match_create(self.socket, self.gamename)
		pprint(match_data)
	else 
		match_callback(false)
	end
end


-- leave a match
local function leave_match(match_id)
	nakama.sync(function()
		log("Sending match_leave message")
		local result = realtime.match_leave(socket, match_id)
		if result.error then
			log(result.error.message)
			pprint(result)
		end
	end)
end

-- find an opponent (using the matchmaker)
-- and then join the match
local function find_opponent_and_join_match(match_callback)
	
	realtime.on_matchmaker_matched(socket, function(message)
		local matched = message.matchmaker_matched
		if matched and (matched.match_id or matched.token) then
			join_match(matched.match_id, matched.token, match_callback)
		else
			match_callback(nil)
		end
	end)

	nakama.sync(function()
		log("Sending matchmaker_add message")
		-- find a match with any other player
		-- make sure the match contains exactly 2 users (min 2 and max 2)
		local result = realtime.matchmaker_add(socket, 2, 2, "*")
		if result.error then
			log(result.error.message)
			pprint(result)
			match_callback(nil)
		end
	end)
end

-- ---------------------------------------------------------------------------
local function updateaccount(self, callback)

	local newUsername = self.player_name
	local display_name = self.player_name
	local avatar_url = "https://example.com/imposter.png"
	local lang_tag = "en"
	local location = ""
	local timezone = ""
	
	local sent = {
		avatar_url, display_name, lang_tag, location, timezone, newUsername
	}

	local result = nakama.update_account(self.client, avatar_url, display_name, lang_tag, location, timezone, newUsername)
	sent.error = result
	callback(sent)
end 

-- -- ---------------------------------------------------------------------------
-- -- This is quite slow, only need a small portion of this. Example only.
-- local function make_requestgamestate(client, game_name, device_id) 

-- 	-- User submission data must be in this format - will be checked
-- 	local userdata = {

-- 		state       = nil,   
-- 		uid         = device_id,
-- 		name        = game_name,
-- 		round       = 0,
-- 		timestamp   = os.time(),

-- 		event       = USER_EVENT.REQUEST_GAME,
-- 		json        = "",
-- 	}
-- 	return userdata
-- end 

-- -- ---------------------------------------------------------------------------
-- -- A normal updategame does a "request_round" event with no other data sent
-- local function updategame(self, callback) 

-- 	local ok, resp = check_connect(self) 
-- 	if(ok == nil) then callback(resp); return nil end 
-- 	if(self.game == nil) then return end 

-- 	local body = make_requestgamestate( self.swp_client, self.game_name, self.device_id)
-- 	local bodystr = json.encode(body)
-- 	swampy.game_update( self.swp_client, self.game_name, self.device_id, function(data)

-- 		if(data.status == "OK") then 
-- 			callback(data.result)
-- 		else 
-- 			print("Error updating game: ", data.results)
-- 			callback(nil)
-- 		end 
-- 	end, bodystr)
-- end 

-- -- ---------------------------------------------------------------------------
-- -- An update that doesnt return anything, just keeps connect alive
-- local function pollgame(self) 

-- 	local ok, resp = check_connect(self) 
-- 	if(ok == nil) then print(resp.status); return nil end 

-- 	local body = make_requestgamestate( self.swp_client, self.game_name, self.device_id )
-- 	body.event = USER_EVENT.POLL
-- 	local bodystr = json.encode(body)
-- 	swampy.game_update( self.swp_client, self.game_name, self.device_id, function(data)
-- 		-- Can do stuff here if you need something to happen ;)
-- 	end, bodystr)
-- end 

-- ---------------------------------------------------------------------------

-- local function sendplayerdata(self, pstate)

-- 	local ok, resp = check_connect(self) 
-- 	if(ok == nil) then callback(resp); return nil end 

-- 	local body = make_requestgamestate( self.swp_client, self.game_name, self.device_id )
-- 	body.state = pstate
-- 	body.event = USER_EVENT.PLAYER_STATE
-- 	local bodystr = bser.serialize(body)
-- 	swampy.game_update( self.swp_client, self.game_name, self.device_id, function() end, bodystr)
-- end 

-- send move as match data
local function send_player_move(match_id, row, col)
	nakama.sync(function()
		local data = json.encode({
			row = row,
			col = col,
		})
		log("Sending match_data message")
		local result = realtime.match_data_send(socket, match_id, OP_CODE_MOVE, data)
		if result.error then
			log(result.error.message)
			pprint(result)
		end
	end)
end

-- ---------------------------------------------------------------------------

-- local function reqround(self, callback)

-- 	local ok, resp = check_connect(self) 
-- 	if(ok == nil) then callback(resp); return nil end 

-- 	local body = make_requestgamestate( self.swp_client, self.game_name, self.device_id )
-- 	body.event = USER_EVENT.REQUEST_ROUND
-- 	local bodystr = bser.serialize(body)
-- 	swampy.game_update( self.swp_client, self.game_name, self.device_id, function(data) 
-- 		callback(data)
-- 	end, bodystr)
-- end 

-- ---------------------------------------------------------------------------
-- handle received match data
-- decode it and pass it on to the game
local function handle_match_data(match_data)
	local data = json.decode(match_data.data)
	local op_code = tonumber(match_data.op_code)
	if op_code == OP_CODE_STATE then
		warbattles.match_update(data.state, data.active_player, data.other_player, data.your_turn)
	else
		log(("Unknown opcode %d"):format(op_code))
	end
end

-- ---------------------------------------------------------------------------
-- handle when a player leaves the match
-- pass this on to the game
local function handle_match_presence(match_presence_event)
	if match_presence_event.leaves and #match_presence_event.leaves > 0 then
		warbattles.opponent_left()
	end
end

-- ---------------------------------------------------------------------------

-- local function reqpeople(self, callback)

-- 	local ok, resp = check_connect(self) 
-- 	if(ok == nil) then callback(resp); return nil end 

-- 	local body = make_requestgamestate( self.swp_client, self.game_name, self.device_id )
-- 	body.event = USER_EVENT.REQUEST_PEOPLE
-- 	local bodystr = bser.serialize(body)
-- 	swampy.game_update( self.swp_client, self.game_name, self.device_id, function(data) 
-- 		callback(data)
-- 	end, bodystr)
-- end 


-- ---------------------------------------------------------------------------

-- local function waiting(self)

-- 	local ok, resp = check_connect(self) 
-- 	if(ok == nil) then print(resp.status); return nil end 
-- 	if(self.game == nil) then pprint("Invalid Game: ", self.game); return end 

-- 	local body = make_requestgamestate( self.swp_client, self.game_name, self.device_id )
-- 	body.state = self.game.state or { event = GAME.GAME_JOINING }
-- 	body.event = USER_EVENT.REQUEST_WAITING
-- 	local bodystr = json.encode(body)
-- 	pprint("WAITING: "..tostring(body.state))
-- 	swampy.game_update( self.swp_client, self.game_name, self.device_id, function(data)

-- 		-- The game is returned on start - use this for game obj
-- 		if(data.status ~= "OK") then 
-- 			print("Error updating scenario: ", data.results)
-- 		end 
-- 	end, bodystr)
-- end 

-- ---------------------------------------------------------------------------

-- local function doupdate(self, callback)

-- 	updategame(self, function(data) 

-- 		-- Replace incoming data for the game object 
-- 		if(data) then 
-- 			self.game = data

-- 			if(self.game) then 
-- 				updategamestate(self, function(data)
-- 					self.round = tmerge(self.round, data)
-- 					if(callback) then callback(data) end
-- 					if(self.game == nil or self.game.state == nil) then return end
-- 					if(self.gamestate ~= self.game.state) then 
-- 					end
-- 				end)
-- 			end

-- 			-- Something has kicked us out return to previous page
-- 		else
-- 			self.swp_account = nil 
-- 			self.game = nil
-- 		end
-- 	end)
-- end 

-- -- ---------------------------------------------------------------------------
-- -- Just a wrapper in case want to insert extra functionality
-- local function findgame( self, gamename, callback )

-- 	local ok, resp = check_connect(self) 
-- 	if(ok == nil) then callback(resp); return nil end 

-- 	swampy.game_find( self.swp_client, gamename, self.device_id, callback, nil )
-- end

-- -- ---------------------------------------------------------------------------
-- -- Just a wrapper in case want to insert extra functionality
-- local function creategame( self, gamename, callback )

-- 	local ok, resp = check_connect(self) 
-- 	if(ok == nil) then callback(resp); return nil end 

-- 	local limit = 10 -- 10 players - this is not being used in MyGame.
-- 	swampy.game_create( self.swp_client, gamename, self.device_id, limit, function(data)
-- 		self.game_name = gamename 
-- 		callback(data)
-- 	end )
-- end

-- -- ---------------------------------------------------------------------------

-- local function joingame( self, gamename, callback )

-- 	local ok, resp = check_connect(self) 
-- 	if(ok == nil) then callback(resp); return nil end 

-- 	swampy.game_join( self.swp_client, gamename, self.device_id, function(data)
-- 		self.game_name = gamename 
-- 		callback(data)
-- 	end, nil )
-- end

-- -- ---------------------------------------------------------------------------

-- local function leavegame( self, gamename, callback )

-- 	local ok, resp = check_connect(self) 
-- 	if(ok == nil) then callback(resp); return nil end 

-- 	swampy.game_leave( self.swp_client, gamename, self.device_id, callback, nil )
-- end

-- -- ---------------------------------------------------------------------------

-- local function closegame( self, gamename, callback )

-- 	local ok, resp = check_connect(self) 
-- 	if(ok == nil) then callback(resp); return nil end 

-- 	swampy.game_close( self.swp_client, gamename, self.device_id, callback, nil )
-- end

-- login to Nakama
-- setup listeners
-- * socket events from Nakama
-- * events from the game
local function login(self, callback)

	-- enable logging
	log.print()

	-- create server config
	-- we read server url, port and server key from the game.project file
	local config = {}
	config.host = sys.get_config_string("nakama.host", HOST)
	config.port = sys.get_config_number("nakama.port", PORT)
	config.use_ssl = (config.port == 443)
	config.username = sys.get_config_string("nakama.server_key", "defaultkey")
	config.password = ""
	config.engine = defold

	self.client = nakama.create_client(config)

	nakama.sync(function()
		-- Start by doing a device login (the login will be tied
		-- not to a specific user but to the device the game is
		-- running on)
		local ok = device_login(self.client)
		if not ok then
			callback(false, "Unable to login")
			return
		end

		-- the logged in account
		self.account = nakama.get_account(self.client)

		-- Next we create a socket connection as well
		-- we use the socket connetion to exchange messages
		-- with the matchmaker and match
		self.socket = nakama.create_socket(self.client)

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
			handle_match_presence(message.match_presence_event)
		end)

		-- Called by Nakama when the game state has changed.
		-- We parse the data and send it to the game.
		realtime.on_match_data(self.socket, function(message)
			log("nakama.on_matchdata")
			handle_match_data(message.match_data)
		end)

		-- This will get called by the game when the player pressed the
		-- Join button in the menu.
		-- We add the logged in player to the matchmaker and join a match
		-- once one is found. We then call the provided callback to let the
		-- game know that it can proceed into the game
		warbattles.on_join_match(function(callback)
			log("warbattles.on_join_match")
			find_opponent_and_join_match(callback)
		end)

		-- Called by the game when the player pressed the Leave button
		-- when a game is finished (instead of waiting for the next match).
		-- We send a match leave message to Nakama. Fire and forget.
		warbattles.on_leave_match(function()
			log("warbattles.on_leave_match")
			leave_match(match.match_id)
		end)

		-- Called by the game when the player is trying to make a move.
		-- We send a match data message to Nakama.
		warbattles.on_send_player_move(function(row, col)
			log("warbattles.on_send_player_move")
			send_player_move(match.match_id, row, col)
		end)

		callback(true)
	end)
end

-- ---------------------------------------------------------------------------
return {
	-- setup 			= setup_swampy,
	login 			= login,
	-- connect 		= connect,
	updateaccount 	= updateaccount,
	resetclient		= resetclient,

	-- websocket_open	= websocket_open,
	-- websocket_close = websocket_close,
	-- websocket_send	= websocket_send,
		
	join_match		= join_match,

	-- creategame 		= creategame,
	-- findgame		= findgame,
	-- joingame		= joingame,
	-- leavegame		= leavegame,
	-- closegame		= closegame,

	-- updategame		= updategame,
	-- pollgame		= pollgame,
	-- doupdate		= doupdate,
	-- updateready		= updateready,
	-- startgame		= startgame,
	-- exitgame		= exitgame,

	-- sendplayerdata	= sendplayerdata,

	-- reqround 		= reqround,
	-- reqpeople 		= reqpeople,

	-- waiting 		= waiting,

	EVENT 			= USER_EVENT,
}

-- ---------------------------------------------------------------------------
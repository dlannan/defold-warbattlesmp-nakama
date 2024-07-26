# defold-warbattlesmp-nakama
A multiplayer version of warbattles using nakama and direct match connection using a match name.

The matches will be limited to 4 players (to keep performance reasonable).

The Server code is in the Server folder: server/modules

Additionally a docker0-compose.yml file is provided that starts up a compelte nakama server ready for use with an added OpenSSH server included so you can ssh into the running Nakama Server and examine logs, upload modules and so on. 

## SWAMPY

The whole codebase is converted from my own SWAMPY server system that has a running warbattlesmp module.

Client: https://github.com/dlannan/defold-warbattlesmp

Server: https://github.com/dlannan/swampy

SWAMPY is a a work in progress server. And is currently undergoing some core changes where all running game modules will run in their own process with their own restricted lua environment. This makes SWAMPY quite secure, as well as being very flexible.

With the above in mind, it is important to note that alot of the code has been "adjusted" to work with Nakama and is probably not always optimally designed to work with Nakama. The core idea of this project is to provide a complete sample of a realtime (or near realtime) game that can be used with Nakama, including server code.

## Design

The main structure of the game is:
- User starts app
- Game name is generated or it can be entered (to join a game)
- User name is auto generated (its easy enough to add a panel to modify the user name as an exercise for the developer)
- User connects to or creates a game. The client will request to create a game with the given name if it cannot find one to connect to. This uses RPC, because I didnt want to use any match-making services.
- Once connected the game sends initializers for where the tanks were started (so the client can do the same) and begins sending updates 1 per second in the main loop on the server. 
- The main loop does _not_ update all player states all the time. All player events are separately broadcast depending on the event types.
- As the player moves, the server is updated, and then the server updates other players. Sometimes these updates are coalesced to minimize server output. 
- Weapons and explostions are events that are simulated local and sent to other players. The server decides on any state conflicts. ie if player X beats player Y to destroy a tank. 

The whole game is intended as a simplistic demo, not a completed game.
However, there should be enough example code of how to do many different network related operations on both client and server so as to help people to develop complete game code themselves.

## Important - Disclaimer and License

The docker image is _not_ secure and should only be used for development and testing. DO NOT use this in production without apply a number of important layers of security to the server. 

This software is provided under an MIT license:

MIT License

Copyright (c) 2024 Kakutai Pty Ltd

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

Note: There are portions of warbattles as well, that are under copyright of other authers. Please examine extensions and headers in code to see appropriate restrictions and license agreements.


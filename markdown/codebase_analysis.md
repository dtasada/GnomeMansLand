# Gnome Man's Land Code Analysis

This document provides a comprehensive analysis of the "Gnome Man's Land" codebase, a 3D multiplayer game built with Zig and Raylib.

## High-Level Architecture

The project follows a client-server model and is designed to run as a single executable that can act as a client, a listen-server (hosting and playing simultaneously), or connect to a remote server.

The core of the application is a state machine that manages the UI and game flow, transitioning between states such as the main menu, server setup, lobby, and the in-game view.

A key architectural feature is the asynchronous server launch. When a user chooses to host a game, a server instance is spawned in a background thread. This server handles the procedural generation of the game world. While the world is being generated, the UI displays a loading screen. Once the server is ready, a client instance is created within the same process, and the application transitions to the in-game state.

## Core Components

### 1. Build System (`build.zig`)

-   **Dependencies:** The project depends on Raylib for graphics and a custom `network` module for networking.
-   **Structure:** It defines the module structure of the application, linking together the client, server, and common components.

### 2. Entry Point ([src/main.zig](/src/main.zig))

-   This is the main entry point of the executable.
-   Its primary responsibility is to create and run the central `Game` object.

### 3. Game Wrapper ([src/client/game/Game.zig](/src/client/game/Game.zig))

-   This is the core wrapper for the entire application.
-   It holds instances of the `client` and `server` (if hosting).
-   It manages the main state machine that drives the application's flow.
-   The `loop` function in this file is the main game loop.

### 4. State Machine ([src/client/state/State.zig](/src/client/state/State.zig))

-   Implements the central state machine that controls the application's UI and game flow (e.g., `Lobby`, `InGame`, `ServerSetup`).
-   Contains the critical logic for spawning the server instance in a background thread (`hostServer`) and for creating the client instance (`openGame`).

### 5. In-Game State ([src/client/state/InGame.zig](/src/client/state/InGame.zig))

-   Contains the primary gameplay loop.
-   Manages the rendering pipeline, which uses Raylib and custom GLSL shaders for lighting.
-   Handles client-side processing of world data, such as generating 3D models from the height map received from the server.
-   Displays a loading screen while waiting for world data.

## Networking ([src/socket_packet.zig`, `src/client/Client.zig`, `src/server/Server.zig](/src/socket_packet.zig`, `src/client/Client.zig`, `src/server/Server.zig))

The networking layer is a fundamental part of the application, enabling multiplayer functionality.

### 1. Communication Protocol

-   **Transport:** Communication occurs over TCP.
-   **Format:** Messages are JSON objects, separated by newline characters (`\n`).
-   **Message Identification:** Each JSON message contains a `descriptor` field, which is an enum that identifies the type of the message.

### 2. Message Definitions ([src/socket_packet.zig](/src/socket_packet.zig))

This file defines the structure of all network messages. Key message types include:

-   `ClientConnect`: Sent by a client to join the server, containing the player's nickname.
-   `WorldDataChunk`: Sent by the server to a client, containing a piece of the world's height map. The world data is split into chunks to avoid sending a single large message.
-   `Player`: Sent by the server to update clients on the state of a player (e.g., position).
-   `MovePlayer`: Sent by a client to inform the server of its new position.
-   `ServerFull`: Sent by the server if a client attempts to connect when the server is at maximum capacity.

### 3. Server ([src/server/Server.zig](/src/server/Server.zig))

-   The server listens for incoming TCP connections on a specified port.
-   For each connected client, the server spawns two threads:
    -   One for receiving messages (`handleClientReceive`).
    -   One for sending game state updates (`handleClientSend`).
-   When a new client connects, the server adds them to the game and begins sending the world data in chunks.
-   The server periodically broadcasts the state of all players to all clients to maintain synchronization.
-   It processes incoming messages from clients, such as player movement updates, and updates the canonical game state.

### 4. Client ([src/client/Client.zig](/src/client/Client.zig))

-   The client connects to the server using TCP.
-   Upon connecting, it sends a `ClientConnect` message.
-   It starts a listening thread (`listen`) to asynchronously receive messages from the server.
-   It processes incoming messages to update the local game state. This includes:
    -   Receiving `WorldDataChunk` messages and assembling the world height map.
    -   Receiving `Player` state messages and updating the positions of other players.
-   It provides a `send` method for sending messages to the server, such as `MovePlayer` when the local player moves.

## Game Data and World Generation

-   **Server-Side:** The server is responsible for generating and owning the game world. The world's terrain is created using a Perlin noise algorithm to generate a height map ([src/server/Perlin.zig](/src/server/Perlin.zig)).
-   **Client-Side:** The client receives the world data from the server and uses it to generate a 3D mesh for rendering.

## Summary of Application Flow

1.  **Initialization:** The application starts, presenting the user with options to host or join a game.
2.  **Hosting:** If the user chooses to host, a `Server` instance is created in a background thread. This server generates the game world.
3.  **Connection:**
    -   If hosting, a local `Client` instance is created in the main process and connects to the background server.
    -   If joining, the client connects to a remote server address.
4.  **Gameplay Loop:**
    -   The server manages the authoritative game state.
    -   Clients receive world data and render the 3D environment.
    -   Clients send their movement updates to the server.
    -   The server broadcasts player state updates to all clients, ensuring a synchronized experience.
    -   Rendering is performed by Raylib, enhanced with custom GLSL shaders for lighting effects.

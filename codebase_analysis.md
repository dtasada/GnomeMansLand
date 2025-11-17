### Key Issues

1.  **Tangled Dependencies:** The `build.zig` file is configured to build a single executable where client-side modules (`game`, `states`) have a direct dependency on the server's implementation (`Server.zig`).
2.  **"God Object":** `src/client/game/Game.zig` acts as a central "god object" for the client, holding state for UI, rendering, and, most problematically, an optional instance of the entire `Server`.
3.  **Lack of Encapsulation:** Client-side UI code in `src/client/states/ServerSetup.zig` directly accesses the server's internal `game_data` to monitor world generation progress. This makes the code brittle and hard to refactor.
4.  **Protocol-Implementation Coupling:** The `src/socket_packet.zig` module, which should define a neutral communication protocol, depends on the server's internal data types, forcing an indirect dependency from the client to the server's implementation details.

## Proposed High-Level Refactoring Plan

To address these issues, a phased refactoring approach is recommended.

### 1. Decouple Client and Server

The most critical step is to separate the client and server into distinct executables.

*   **Modify `build.zig`:** Update the build script to produce two separate executables: `client` and `server`.
*   **Remove Server Instance from Client:** Remove the `server: ?*Server` field from the `Game` struct in `src/client/game/Game.zig`.
*   **Create a Clear Network Interface:** The client should only know how to connect to an IP and port and send/receive packets defined in `socket_packet.zig`. All direct calls to server code should be replaced with network communication.

### 2. Refactor `socket_packet.zig`

The communication protocol must be independent of both the client and the server implementation.

*   **Remove Server Dependencies:** Remove all `@import("server")` statements from `src/socket_packet.zig`.
*   **Define Plain Data Structures:** Define plain, self-contained data structures for all network communication (e.g., a `PlayerState` struct with `id`, `position`, etc., instead of embedding the `ServerGameData.Player` type).
*   **Server-Side Translation:** The server will be responsible for translating its internal data structures to these network-safe types before sending them to the client.

### 3. Introduce a `LocalServer` Abstraction (Optional)

To preserve the "listen server" functionality in a clean way, you can create an abstraction layer.

*   **Create a `LocalServer` Module:** Create a new module within the client's source tree (e.g., `src/client/local_server.zig`).
*   **Process-Based Communication:** This module would be responsible for spawning the server executable as a separate process. Communication between the client and the local server would happen via standard network sockets (e.g., connecting to `127.0.0.1`). This maintains a strong architectural boundary.

### 4. Break Down the `Game` God Object

The `Game.zig` "god object" should be broken down into smaller, more focused modules.

*   **Identify Responsibilities:** Identify the core responsibilities currently managed by `Game.zig`, such as graphics, state management, and network communication.
*   **Create New Modules:** Gradually move these responsibilities into new, more focused modules (e.g., a `Graphics` module, a `StateManager` module, a `NetworkClient` module).

## Conclusion

These changes will lead to a more modular, maintainable, and scalable codebase. By decoupling the client and server, you will be able to develop and deploy them independently. A clean separation of concerns will also make the code easier to understand, debug, and extend in the future.

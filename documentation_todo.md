# Code Documentation To-Do List

## Summary of Findings

The codebase has a systemic lack of documentation. While some files have file-level comments, the vast majority of public structs, functions, and their fields are missing doc comments (`///`). This is a significant issue for maintainability.

### Key issues identified:
1.  **Core Architecture is Undocumented:** Critical components like `Server.zig` (server), `Client.zig` (client), and `State.zig` (client state machine) are almost entirely undocumented. This makes it extremely difficult to understand the overall architecture, concurrency models, and data flow.
2.  **Data Structures Lack Field Comments:** Important data structures, such as `ServerSettings` in `commons.zig` and the various packet structs in `socket_packet.zig`, have no comments on their fields, making their purpose and usage ambiguous.
3.  **Complex Logic is Not Explained:** Complex algorithms, especially those involving multi-threading (e.g., `Server.zig`, `socket_packet.zig`), non-blocking I/O, and state management, are not commented, hiding the original author's intent.
4.  **'Red Flag' Comments:** The investigation found several comments such as `// idk why this was necessary` and `// this works for some reason` in `Server.zig`. These indicate a fragile and poorly understood implementation that should be prioritized for refactoring and documentation.

Although the investigation was cut short, the evidence strongly suggests that nearly every `.zig` file in the `src` directory would benefit from a thorough documentation pass. The priority should be on the files listed in the 'RelevantLocations' section, as they represent the core, and most complex, parts of the arespplication.

---

## Files Requiring Documentation

### 1. `/Users/dt/coding/git/GnomeMansLand/src/server/Server.zig`

**Reasoning:** This is the most critical and under-documented file. It implements the entire multi-threaded server logic. None of the core data structures (`Server`, `Client`) or their fields are documented. Key functions for handling threading, networking, and the application protocol are missing comments. Contains highly concerning comments like `// this works for some reason`, indicating a fragile implementation that must be documented.

**Key Symbols to Document:**
- `Server` (struct)
- `Client` (nested struct)
- `init`
- `deinit`
- `handleClientReceive`
- `handleClientSend`
- `listen`

### 2. `/Users/dt/coding/git/GnomeMansLand/src/client/state/State.zig`

**Reasoning:** This file implements the central state machine for the client. It is almost entirely undocumented, including the main `State` struct, its fields, and all public functions that transition between states. The `waitForServer` function contains complex, non-obvious threaded synchronization logic that is completely uncommented.

**Key Symbols to Document:**
- `State` (struct)
- `init`
- `deinit`
- `update`
- `waitForServer`

### 5. `/Users/dt/coding/git/GnomeMansLand/src/socket_packet.zig`
**Reasoning:** Defines the data structures for the entire client-server communication protocol. Most of the packet types are undocumented. The `WorldDataChunk` struct, in particular, uses 'magic numbers' and complex multi-threaded logic to prepare data for networking, none of which is explained.

**Key Symbols to Document:**
- `WorldDataChunk` (struct)
- `ClientConnect` (struct)
- `Player` (struct)
- `MovePlayer` (struct)

### 6. `/Users/dt/coding/git/GnomeMansLand/src/commons.zig`

**Reasoning:** Contains shared utility functions and data structures. While some functions are documented, the fields of the `ServerSettings` struct and its nested `world_generation` struct are completely undocumented, making it unclear what the various server configuration options do.

**Key Symbols to Document:**
- `ServerSettings` (struct)

### 7. `/Users/dt/coding/git/GnomeMansLand/src/main.zig`

**Reasoning:** The application entry point. The `main` function itself lacks a doc comment explaining its role.

**Key Symbols to Document:**
- `main`

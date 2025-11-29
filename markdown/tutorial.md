# Getting Started with Zig and Gnome Man's Land

Welcome to the project! This guide is for you, an experienced game developer coming from a background in dynamic languages like Python and JavaScript. Your experience with Pygame and Raylib is a huge asset, as the core game loop and rendering concepts will be very familiar.

The biggest hurdle will be learning Zig, but the good news is that Zig is designed to be a simple and readable language. Let's dive in.

## A Crash Course in Zig for a high-level developer

Zig is a statically-typed, compiled language. This is the biggest difference from Python or JavaScript, which are dynamically-typed and interpreted.

-   There are two ways to declare a variable: variable, or constant. the corresponding keywords are `var` and `const`. There's optional type inference so you don't need to write all the types out.

    ```zig
    var x = 10; // the type of `x` is unspecified, so it defaults to `comptime_int`
    var y: i32 = 10; // the type of `y` is specified
    const name = "Gnome"; // []const u8 is a string literal
    ```

-   In Zig, variables should be defined at the time of declaration. A statement like `var x: i32;` doesn't compile. Zig prefers to have a value to initialize it to at the time of declaration. If you want a variable to stay undefined for whatever reason, you must declare that explicitly. An undefined variable in Zig looks like this:
    ```zig
    var x: i32 = undefined;
    ```
    An undefined variable must include an explicit type, otherwise the compiler doesn't know what type it is.
    An undefined variable has no initialized value and just contains whatever garbage data happened to be in memory. This is undefined behavior and should be avoided where possible. Sometimes it is necessary though, you'll see this throughout the codebase.

-   **Compilation:** You don't just run the `.zig` file. You compile the entire project into a single executable file. The command for this project is simple:

    ```bash
    zig build
    ```

    This will create an executable in `zig-out/bin/gnome_mans_land`.

    You can also use the following shorthand to build *and* run the program.
    ```bash
    zig build run
    ```
    This will build the executable into `zig-out/bin/gnome_mans_land` and run it for you. This is the recommended way to run the game.

### 1. No Hidden Memory Allocations (No Garbage Collector!)

This is the most important concept to grasp. In Python and JS, a garbage collector automatically cleans up memory for you. Zig gives you full control.

-   **Allocators:** To get memory (e.g., to create an object or a list), you must ask an `allocator` for it.
-   **`defer` and `errdefer`:** You are responsible for freeing the memory you allocate. Zig's `defer` keyword is your best friend here. It schedules an expression to be executed when the current function exits. `errdefer` does the same, but only if the function returns an error.

    ```zig
    fn doSomething(alloc: std.mem.Allocator) !void {
        var list: std.ArrayList(u8) = .{}; // initializes an empty arraylist
        // or for example `std.ArrayList(u8).initCapacity(alloc, 64);` will preallocate space for 64 integers.
        try list.append(alloc, 69);
        defer list.deinit(alloc); // This will run at the end of the function, freeing the list's memory.
        // or `errdefer list.deinit()`. this will only happen if the function returns an error. note that in this example you wouldn't want that because you wanna clean up the memory no matter what.
        // ... do stuff with the list ...
    }
    ```

    **Think of it like this:** For every `init` or `create` call, you should have a corresponding `deinit` or `destroy` call in a `defer` statement.

-   Practically: whenever a function has to perform operations on the heap, like allocating or deallocating memory, it needs an allocator. A common example:
```zig
const std = @import("std");

const MyStruct = struct {
    ids: std.ArrayList(u32); // `ids` is an arraylist of 32-bit unsigned integers.

    // this is a method. since it doesn't take a `self`, it can be called using `MyStruct` as a namespace, rather than an object.
    pub fn init() MyStruct {
        return .{ .ids = .{} }; // returns an object with an empty arraylist.
        // the .{} syntax is valid because Zig already knows what type `init` should return. If the type wasn't known you'd maybe use `MyStruct{}` instead.
    }

    pub fn addId(self: *MyStruct, allocator: std.mem.Allocator, id: u32) !void {
        // important convention: the allocator should be the first parameter in the function (excluding the `self` parameter)
        try self.ids.append(allocator, id);
    }

    pub fn deinit(self: *MyStruct, allocator: std.mem.Allocator) void {
        self.ids.deinit(allocator);
    }
}

pub fn main() !void {
    const allocator = std.heap.page_allocator; // example allocator: basic OS page allocator

    const my_object = MyStruct.init();
    defer my_object.deinit(allocator); // defer deinitialization so it *always* happens, regardless of if something fails down the line.

    try my_object.addId(allocator, 42);
}
```

This practice of passing allocators is useful because that means that allocators are modular. If you want a different memory allocator for whatever reason, you can change the allocator you pass to the function. Examples are `DebugAllocator`, `WasmAllocator`, `FixedBufferAllocator`, and `ThreadSafeAllocator`.

### 2. Explicit Error Handling

Instead of `try...catch` blocks for exceptions, Zig uses error return types. A function that can fail returns `!void` or `!MyType`.
A function that returns an error union of `ErrorType!SuccessType` returns *either* an `ErrorType` *or* a `SuccessType`.
You can let a function "throw" by just having it return an error. If the function returns a value of `SuccessType`, expected behavior follows.

```zig
// A function that might fail to read a file
fn readFile() ![]u8 {
    // ...
    if (file_read_successfully) {
        return file_string;
    } else {
        return error.CouldNotReadFile;
    }
}

fn myFunc() !void {
    // The 'try' keyword is like '.unwrap()' or 'await'. If readFile() returns an error,
    // myFunc() will immediately stop and return that same error.
    // `try` and `catch` are mutually exclusive.
    const try_file_contents = try readFile();
    const default_file_contents = readFile() catch "Default value"; // will call readFile, and if it returns an error, evaluates the `catch` expression.
    const catch_file_contents = readFile() catch |err| {
        // this not only catches, but captures the error value itself. This is comparable to an enum, it's just an arbitrary value identifiable by a name.
        // now we can perform arbitrary logic on that `err` value, like printing it to stdout.
        std.debug.print("err: {}\n", .{err});
        // `catch_file_contents` expects a string, but since we return early, any code after this block is unreachable, so Zig compiles it just fine.
        return err;
    }

    // ...
}
```

The `try` keyword is a syntactic shorthand for `catch |err| return err`. This just takes whatever error the function call returned, and returns it into the current function.

### 3. Optionals

In Zig, there's another kind of built-in union type: the optional. An optional, or nullable type denotes that a variable may also be `null`, along with its normal type.
```zig
var my_optional: ?i32 = null;
```
Prefixing a `?` before a type creates an optional type. Just like `try` and `catch`, there's syntactic shorthands for dealing with optionals.
```zig
if (my_optional) |value| { 
    // extracts inner value from optional. since `my_optional` is an optional, it can't be used directly just by name
    // the inner value must be extracted first.
    // now, `value` is of type `i32`. Since this is an if statement, this block only executes if `my_optional != null`.
}
const assert_value: i32 = my_optional.?; // the `.?` operator asserts that `my_optional` is not null, but will crash the program at runtime if it is.
const default_value: i32 = my_optional orelse 69; // the `orelse` operator works only on optional values and returns either the inner value of an optional, or a default value if the optional equals `null`. It behaves kind of like the `catch` operator.
```

### 4. Pointers
Pointers work just like in C. Prefixing a type with `*` marks it as a pointer type.
```zig
my_pointer: *i32
```
Pointers may also not be null to avoid null pointer exceptions. Of course you can emulate that behavior by explicitly making the pointer nullable as well: `my_pointer: ?*i32`.
You can suffix pointers with `const` to make sure the user can't modify the contents at the pointer.
```zig
fn mutable(value: *i32) void {
    value.* = 1; // dereference a pointer with `.*` and set the value behind the pointer to `1`.
}

fn constant(value: *const i32) void {
    value.* = 1; // this won't compile because `*const i32` is not a mutable type.
}

fn safeNullable(value: ?*i32) void {
    if (value) |inner| {
        std.debug.print("argument has a value! {}\n", .{inner.*});
    } else {
        std.debug.print("argument is null :(", .{});
    }
}
```
Since we prefer immutability by default and explicit mutability, please default to a habit of passing pointers by `*const T` unless you need to mutate the pointee. Also default to `const` instead of `var`. If a variable is declared with `var`, but it is never mutated, the compiler will tell you with an error.

### 5. Expressions
```zig
// if expression
const myValue = if (some_condition)
        some_value
    else
        other_value;

// switch statement
const anotherValue = switch (myEnum) {
    .a => value_corresponding_to_a,
    .b => value_corresponding_to_b,
    .c => value_corresponding_to_c,
};

// block expression
const blockValue = b: {
    // in zig, you can label blocks to make them behave as expressions.
    // the label `b` is arbitrary but `b` or `blk` are conventional.

    // do any arbitrary processing
    const my_result = ...;

    // now i can `break` using the label name, along with a value, and the block `b` will evaluate to whatever value was broken with.
    break :b my_result; // basically returns the block with `my_result`
};
```

### 6. Syntactic shorthands
In Zig, there's a few syntactic shorthands that allow for easier typing when a type is already known.
```zig
const MyEnum = enum { a, b, c };

const MyStruct = struct {
    some_enum: MyEnum,

    pub fn init() MyStruct {
        return .{
            // since we already know `some_enum` is of type `MyEnum` (because it's in the struct definition),
            // we can just write `.a` instead of `MyEnum.a` (which is also valid).
            .some_enum = .a; 
        };
    }
};

pub fn main() !void {
    var my_object: MyStruct = .init(); // since we know `my_object` is of type `MyStruct`, we can just call `.init()` instead of `MyStruct.init()`.
}
```
I like using the shorthand for enums, but for structs i'm less liberal with it because it can sometimes get a little unclear what the type is anymore.
You'll see a mix of it being used and it not being used throughout the codebase, but it's kinda context dependent.

### 7. Number casting
In the vein of explicitness, Zig is kind of difficult with casting numbers to different types.
```zig
const my_integer: i32 = 42;
const my_float: f32 = @floatFromInt(my_integer); // since float -> int is a pretty important and error-prone operation, zig makes sure it's painful to write.
const other_integer: u64 = @intCast(my_integer); // to cast an integer type to a different integer type, we use `@intCast`.
const sum = @as(u64, @intCast(my_integer)) + other_integer;
```
Number arithmetic can only be used with numbers of the same type. that means we want to cast `my_integer` to the same type as `other_integer` before we add them together. Since we're doing this inline, and the target type isn't known, we use `@as` to make sure zig knows we're casting to a `u64`. When declaring `other_integer`, `@as` wasn't necessary because the type is specified in the type signature. If we were not to declare the type, we'd have to write `const other_integer = @as(u64, @intCast(my_integer))`. As you can see, just writing the type is cleaner, but they both do the same thing.

### 8. Tuples and anytype
For the purposes of safety and explicitness, Zig doesn't have variadic types (that's when a function takes any number of arguments, this is usually expressed with `...`, or `*` in python). Instead, a function that requires an arbitrary number of values will always take in one argument. For example, the default debug printing function, `std.debug.print` takes exactly two arguments: the format string, and a tuple, which will be empty if you don't need any variables, or contain any amount of elements if you do. To print some string, you'll have to write `std.debug.print("some string\n", .{})`. Notice the `.{}`: this is the empty tuple.

### 9. `comptime` - The Compiler is Your Friend

Zig can run code at compile-time. This is used for things like metaprogramming, validating types, and setting up data structures without any runtime cost. You'll see the `comptime` keyword used to make the code more efficient and flexible.

## How This Project is Structured

Now, let's look at the codebase. We've tried to structure it like a simple game engine.

-   [build.zig](/build.zig): This is the "entry point" for the compiler. It tells Zig how to build the project, what the dependencies are (like Raylib), and which files to include.
-   [src/main.zig](/src/main.zig): The actual entry point for the *program*. It's very simple: it just initializes the main `Game` object and starts the game loop.
-   [src/client/game/Game.zig](/src/client/game/Game.zig): This is the heart of the client application. It owns the main `state` machine. The `loop()` function here is the main game loop.
-   [src/client/state/State.zig](/src/client/state/State.zig): This file defines the game's state machine. A "state" is basically a screen, like the main menu (`Lobby.zig`), the settings screen, or the game itself (`InGame.zig`). The state machine controls which state is currently active and being updated/drawn.
-   [src/server/Server.zig](/src/server/Server.zig) & [src/client/Client.zig](src/client/Client.zig): These handle all the networking. The server manages the game world and player data, while the client sends input and receives updates.

## Where to Start Making Changes

Here are some common tasks and where to look in the code to implement them.

-   **"I want to change the main menu..."**
    -   Look at [src/client/state/Lobby.zig](/src/client/state/Lobby.zig). This file controls the logic and UI for the main menu. The UI elements are drawn using functions from [src/client/state/ui.zig](/src/client/state/ui.zig).

-   **"I want to change how the player moves..."**
    -   Player input is handled in [src/client/game/input.zig](/src/client/game/input.zig). The `handleKeys` function is where keyboard input is translated into actions.
    -   These actions (like moving) are sent to the server. The server processes the movement in [src/server/Server.zig](/src/server/Server.zig) in the `processMessage` function, specifically for the `.move_player` descriptor.

-   **"I want to add a new enemy or object..."**
    -   This is a great place to start! Currently, the project doesn't have a generic "GameObject" or "Entity" system (this is a planned architectural improvement).
    -   To see how players are handled, look at [src/server/GameData.zig](/src/server/GameData.zig) where the `Player` struct is defined. The server updates a list of these players.

-   **"I want to change how the world looks or is generated..."**
    -   The 3D rendering happens in [src/client/state/InGame.zig](/src/client/state/InGame.zig). This is where the 3D models are drawn.
    -   The shaders are in [resources/shaders](/resources/shaders).
    -   The world *generation* happens on the server side, in [src/server/Perlin.zig](/src/server/Perlin.zig), which uses Perlin noise to create the height map.

Don't be afraid to experiment and break things. The compiler is very helpful and will often tell you exactly what's wrong. Welcome aboard!

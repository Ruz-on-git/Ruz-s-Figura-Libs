# RuzUtils

Ruz Utils is a simple libary of utility commands i use with my other libraries.

---

## Index

- [Installation](#installation)  
- [Usage](#usage)  
  - [1. Scheduler](#1-scheduler)  
  - [2. Logging](#2-logging)  
  - [3. Player & Entity Utilities](#3-player--entity-utilities)  
  - [4. File I/O](#4-file-io)  
  - [5. Command Manager](#5-command-manager)  
- [API Documentation](#api-documentation)  
  - [Scheduler Functions](#scheduler-functions)  
  - [Logging Functions](#logging-functions)  
  - [Entity & Player Functions](#entity--player-functions)  
  - [File I/O Functions](#file-io-functions)  
  - [Command Manager Functions](#command-manager-functions)  

---

## Installation

Place **RuzsUtils** into your model folder.  
By default the module expects this structure:

```
Main Folder/
 └─ APIs/
     └─ RuzsUtils/
          RuzsUtils.lua
          commandManager.lua
```

Then require as normal:

```lua
local RuzUtils = require("APIs.RuzsUtils.API")
```

RuzUtils automatically initializes its CommandManager on import.

---

## Usage

---

## 1. Scheduler

Run code **after a delay in ticks** (20 ticks = 1 second).

### Schedule a function:

```lua
local id = RuzUtils.runAfterDelay(40, function(msg)
    print("Executed: " .. msg)
end, "Hello world!")
```

### Cancel a scheduled task:

```lua
local ok = RuzUtils.cancelTask(id)
```

---

## 2. Logging

Logs text using JSON formatting inside chat.

```lua
RuzUtils.log("Loading config...", "yellow", '{"text":"[","color":"white"},{"text":"Config","color":"gold"}')
```

---

## 3. Player & Entity Utilities

### Check if a UUID is valid:

```lua
if RuzUtils.isValidUUID(uuid) then
    print("Valid!")
end
```

### Find a player (name or UUID):

```lua
local p = RuzUtils.findPlayer("PlayerName")
```

### Find a player by UUID only:

```lua
local p = RuzUtils.findPlayerFromUUID(uuid)
```

### Raycast for the entity the player is looking at:

```lua
local target = RuzUtils.getLookingAtEntity(25)
```

---

## 4. File I/O

### Read internal resource files:

```lua
local text = RuzUtils.readResource("assets/myfile.txt")
```

### Read external files (File API permission required):

```lua
local contents = RuzUtils.readDataFile("data/config.json")
```

---

## 5. Command Manager

Create complex command structures with prefixes, root commands, subcommands, and nested commands.

### Create a command set:

```lua
local config = {
    PREFIX = "!",
    ROOT = { aliases = {"test"} },
    SUBCOMMANDS = {
        ping = { aliases = {"p"} },
        echo = { aliases = {"e"} }
    }
}

local handlers = {
    ping = function(args)
        RuzUtils.log("Pong!")
    end,
    
    echo = function(args)
        RuzUtils.log(table.concat(args, " "))
    end,

    help = function()
        RuzUtils.log("Available commands: ping, echo")
    end
}

RuzUtils.CommandManager:registerCommandSet(config, handlers, "[TestModule]")
```

### Usage examples:

```
!test ping
!test echo hello world
```

---

# API Documentation

Below is full documentation for each function.

---

## Scheduler Functions

---

### `runAfterDelay(ticks, func, ...)`

Schedules a function to run after a delay.

**Parameters:**

| Name  | Type      | Description |
|-------|-----------|-------------|
| `ticks` | `number` | Delay in ticks (20 = 1 second). |
| `func`  | `function` | Function to execute after the delay. |
| `...`   | `any` | Optional arguments passed to the function when executed. |

**Returns:**

| Type | Description |
|------|-------------|
| `number` | The unique task ID assigned. |

---

### `cancelTask(id)`

Cancels a previously scheduled task.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `id` | `number` | The task ID returned from `runAfterDelay`. |

**Returns:**

| Type | Description |
|------|-------------|
| `boolean` | True if found & removed; false otherwise. |

---

## Logging Functions

---

### `log(msg, color, prefix, submodule)`

Logs a formatted JSON message to chat.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `msg` | `any` | The message text to log. |
| `color` | `string?` | Optional text color. Defaults to `"white"`. |
| `prefix` | `string?` | Optional JSON prefix override. |
| `submodule` | `string?` | Optional module label appended to the prefix. |

**Returns:**  
Nothing.

---

## Entity & Player Functions

---

### `isValidUUID(uuid)`

Checks whether a UUID corresponds to a loaded avatar.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `uuid` | `string` | UUID to check. |

**Returns:**

| Type | Description |
|------|-------------|
| `boolean` | True if a valid avatar exists. |

---

### `findPlayerFromUUID(uuid)`

Gets a player entity if loaded.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `uuid` | `string` | UUID of the player. |

**Returns:**

| Type | Description |
|------|-------------|
| `Player?` | Player entity or nil. |

---

### `findPlayer(id)`

Gets a player by **name or UUID**.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `id` | `string` | Username or UUID. |

**Returns:**

| Type | Description |
|------|-------------|
| `Player?` | Entity or nil. |

---

### `getLookingAtEntity(range)`

Raycasts to find the entity the player is looking at.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `range` | `number?` | Max raycast distance (default: 20). |

**Returns:**

| Type | Description |
|------|-------------|
| `Entity?` | Target or nil. |

---

## File I/O Functions

---

### `readResource(path)`

Reads a packaged internal resource file.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `path` | `string` | Internal resource path. |

**Returns:**

| Type | Description |
|------|-------------|
| `string?` | File content or nil on failure. |

---

### `readDataFile(path)`

Reads an external file (File API required).

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `path` | `string` | File path. |

**Returns:**

| Type | Description |
|------|-------------|
| `string?` | Contents of the file or nil. |

---

## Command Manager Functions

---

### `CommandManager.new(utils)`

Initializes the global command manager.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `utils` | `RuzUtilsAPI` | RuzUtils instance. |

**Returns:**

| Type | Description |
|------|-------------|
| `CommandManager` | The shared manager instance. |

---

### `registerCommandSet(config, handlers, logPrefix)`

Registers a new command set.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `config` | `table` | Structure defining prefixes & subcommands. |
| `handlers` | `table<string, function|table>` | Functions or nested tables to call. |
| `logPrefix` | `string` | Prefix used in log output. |

**Returns:**  
Nothing.

---

### `handle(set, msg)` *(Internal)*

Processes messages for the matching command set.

**You normally **do not** call this manually.**

---
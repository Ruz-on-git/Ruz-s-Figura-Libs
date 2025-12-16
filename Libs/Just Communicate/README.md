# JustCommunicate

Just Communicate is a libary used for sending large amounts of data to other users privatly, using tellraw. 

It requires both players to have an instance of Just Communicate running on their avatar, and for sending messages to be enabled.

------------------------------------------------------------------------

## Index

-   [Installation](#installation)
-   [Setup](#setup)
-   [Whitelist System](#whitelist-system)
-   [Messaging API](#messaging-api)
-   [Commands](#commands)
-   [Configuration](#configuration)
-   [Full Example Config](#full-example-config)

------------------------------------------------------------------------

## Installation

Place JustCommunicate inside your `APIs` folder, then require it:

``` lua
local JC = require("APIs.JustCommunicate.API")
```

JustCommunicate depends on:

-   [Ruz Utils](https://github.com/Ruz-on-git/Ruz-s-Figura-Libs/tree/main/Libs/Ruz%20Utils)
-   [ExtendedJson](https://github.com/Ruz-on-git/Ruz-s-Figura-Libs/blob/main/Libs/ExtendedJson.lua)
-   [WhitelistMe](https://github.com/Ruz-on-git/Ruz-s-Figura-Libs/tree/main/Libs/Whitelist%20Me)

Make sure these modules are available in the paths defined in your
`config.lua`.

You will also need to turn on chat messages to allow the system to send json messages to other players.

------------------------------------------------------------------------

## Setup

To enable JustCommunicate, call:

``` lua
JC.init("default")
```

Where `"default"` is the name of the whitelist configuration to load.

If initialization fails the system will automatically disable itself.

------------------------------------------------------------------------

## Messaging API

These functions wrap the Messaging module for easy use:

``` lua
JC.sendMessage(id, payload, sender, priority)
JC.addListener(id, callback)
JC.removeListener(id)
```

### Example

``` lua
JC.addListener("hello", function(data)
    print("Received:", data)
end)

JC.sendMessage("hello", "Testing!", player:getName(), 0)
```

Listeners automatically respect whitelist rules.

------------------------------------------------------------------------

## Commands

JustCommunicate exposes a configurable command system.

Default root command:

    .jc

### Subcommands

#### `.jc help`

Shows all available commands.

#### `.jc whitelist`

Manage global whitelist.

  |Command                  |Description|
  |------------------------ |-----------------------------------------|
  |`.jc wl add <name>`      |Add a name/UUID
  |`.jc wl remove <name>`   |Remove entry
  |`.jc wl set <mode>`      |Set whitelist mode (`*`, `all`, `none`)
  |`.jc wl list`            |Display whitelist

#### `.jc looking`

Manage whitelist of the entity you are currently looking at.

  |Command           | Description
  |------------------ |----------------------------
  |`.jc wll add`      |Add the targeted entity
  |`.jc wll remove`  |Remove the targeted entity

------------------------------------------------------------------------

## Configuration

JustCommunicate uses the following config fields:

-   **MARKER_PREFIX** --- Prefix for outgoing messages
-   **MAX_PAYLOAD_LENGTH** --- Max bytes allowed in a single message
-   **CHECKER** --- Internal self-check settings
-   **LOGTYPES** --- Log color presets
-   **LOG_PREFIX_JSON** --- JSON-formatted log header
-   **COMMANDS** --- Command prefix, root, aliases, and descriptions

If you change command prefixes or aliases, all commands update
automatically.

------------------------------------------------------------------------

## Full Example Config

``` lua
config.JustCommunicate = {
    MARKER_PREFIX = "[JUST_COMM_MSG]",
    MAX_PAYLOAD_LENGTH = 16000,

    CHECKER = {
        MAX_TICKS = 100,
        MARKER_PREFIX = "[JustCommunicate][Internal]:"
    },

    LOGTYPES = {
        ERROR = "red",
        WARNING = "yellow",
        LOG = "white"
    },

    LOG_PREFIX_JSON = table.concat({
        '{"text":"[","color":"white"}',
        '{"text":"Just","color":"green"}',
        '{"text":"Communicate","color":"dark_green"}',
    }, ","),

    COMMANDS = {
        PREFIX = ".",
        ROOT = {
            name = "jc",
            aliases = { "jc", "justcommunicate" }
        },
        SUBCOMMANDS = {
            help = {
                aliases = { "help", "?" },
                desc = "Shows the help menu."
            },

            whitelist = {
                aliases = { "wl", "whitelist" },
                desc = "Manage whitelist manually.",
                subcommands = {
                    add = { desc = "Add a player/UUID.", usage = "<name/uuid>" },
                    remove = { desc = "Remove a player/UUID.", usage = "<name/uuid>" },
                    set = { desc = "Set global mode.", usage = "<*|all|none>" },
                    list = { desc = "List whitelisted players." }
                }
            },

            whitelistLooking = {
                aliases = { "wll", "looking" },
                desc = "Manage whitelist for the entity you are looking at.",
                subcommands = {
                    add = { desc = "Add the target entity." },
                    remove = { desc = "Remove the target entity." }
                }
            }
        }
    }
}
```

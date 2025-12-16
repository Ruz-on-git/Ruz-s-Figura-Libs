# OffloadAnimations

Offload animations is a libary used to allow players to remove animations from their blockbench file to reduce the size, and instead put them in data files which are then streamed at runtime using the figura ping system. This is also the backend that is needed to use Join in Animations, which allows for sycncing animations with another player.

---

## Index

- [Installation](#installation)
- [Simple Setup](#simple-setup)
- [Creating Animations](#creating-animations)
    - [Lua Config](#1-lua-config)
    - [Extractor config](#2-extractor-config)
    - [Animation settings](#3-animation-settings)
- [Configuration](#configuration)
- [API Functions](#api-functions)
  - [playAnimation](#play-animation)
  - [playRawAt](#play-raw-at)
  - [stopAnimations](#stop-animations)
  - [getAllAnimationNames](#get-all-animation-names)
  - [getAnimation](#get-animation)
  - [getAnimationWithAllRoles](#get-animation-with-all-roles)
  - [stopClients](#stop-clients)
  - [loadManifest](#load-manefest)

---

## Installation

Place **Offload Animations** into your model folder and then require it in your file
```lua
local RuzUtils = require("APIs.OffloadAnimations.API")
```

After that you will need to go to your data file for figura, which should be in the same location as your avatars folder, along with cahe and config. If it does not exist create it.

Then create a folder called ```offloadAnimations_Data``` or whatever you name in the config file. In this folder you will place the animation files and manefest.json

You will also need to have the following libaries:
- [Extended Json]()
- [Ruz Utils](https://github.com/Ruz-on-git/Ruz-s-Figura-Libs/tree/main/Libs/Ruz%20Utils)

---
## Simple Setup

To use Offload animations you will need to first extract the animations from your model file. You can do this by running the python script in extracter, or by using the web page [here](https://ruz-on-git.github.io/Ruz-s-Figura-Libs/). 

Once you have the files extracted form the animation, you will need to paste them (including the manefest file) into your data folder set in installation. Then you should be able to get the animations infomation though the api commands bellow.

---
## Creating Animations
Before trying to make your own animations, i would highly suggest looking at the example folder and model file so you can understand how the setup works. The example file has been setup for two player animations, but you can ignore the seccond player unless you are setting up 2 player animations.

#### 1. Lua Config

OffloadAnimations expects your model to have these parts by default:

- root
- head
- body
- leftArm
- rightArm
- leftLeg
- rightLeg

Your Lua config should map these names to the model parts, like this:

```lua
data = {
    modelParts = {
        root = models.model.root,
        head = models.model.root.Head,
        body = models.model.root.Body,
        leftArm = models.model.root.LeftArm,
        rightArm = models.model.root.RightArm,
        leftLeg = models.model.root.LeftLeg,
        rightLeg = models.model.root.RightLeg,
    }
}
```

**Do not rename the keys** on the left side (root, head, body, etc.) unless you fully understand what you’re doing.  
These names are part of the shared format that allows animations to work across players.

You can add extra parts using the same format, but note:  
If another player does not define that part, the animation will not play for it on their end.


#### 2. Extractor config
When exporting animations, you need to update either:

- the Python extractor's config file
- the website's config tab

Match the part names from your Lua config (the left-side keys) with the Blockbench part names:

```json
{
  "player1": {
    "root": "root",
    "head": "Head",
    "body": "Body",
    "leftArm": "LeftArm",
    "rightArm": "RightArm",
    "leftLeg": "LeftLeg",
    "rightLeg": "RightLeg"
  }
}
```

#### 3. Animation Settings

You can add special animation settings by creating folders with specific names.  
The current supported settings are:

### - overrideVanilla
Replaces vanilla animations.

### - lockMovement
Prevents the player from moving while the animation is active.

### - useCamera
Controls camera behavior. Inside this folder:

- **sharedCamera** — The default camera used for all players in the animation. Overrides vanilla camera movement in first person.
- **PxCamera** — Overrides the shared camera for a specific player.

### Enabling / Disabling Settings
Toggle settings by changing the **scale** of the object:

- `0` = off  
- `1` = on

---

If you need this exported in another file format, just ask!


---

## Configuration

OffloadAnimations uses a central `Config.lua` file located in your **main model folder**.  
This file defines:

- Module paths  
- Animation part mappings  
- Networking limits  
- Manifest and data directory paths  
- Default model parent types  
- Logging look & feel  

Below is the full example config.

## Example Configuration File (`Config.lua`)

```lua
---@class OAPaths
---@field dataDirectory string
---@field manifestFile string

---@class OAData
---@field modelParts table<string, ModelPart>
---@field parts table<string, table<string, string>>
---@field defaultTypes table<string, string>

---@class OAConfig
---@field paths OAPaths
---@field data OAData
---@field LOG_PREFIX_JSON string
---@field CURRENT_ANIMATION_KEY string
---@field TICKS_PER_SECOND number
---@field MAX_BYTES_PER_SECOND number
---@field PRECISION number

---@field OffloadAnimations table
---@field RuzUtils table

---@class MainConfig
---@field paths ConfigPaths
---@field OffloadAnimations OAConfig

---@type MainConfig
---@diagnostic disable-next-line
local config = {}
---@diagnostic disable-next-line
config.paths = {}
local p = config.paths

p.APIFolder = "APIs"

p.ExtendedJson = p.APIFolder .. ".ExtendedJson"

p.OffloadAnimations = {Folder = p.APIFolder .. ".OffloadAnimations"}
p.OffloadAnimations.API = p.OffloadAnimations.Folder .. ".API"
p.OffloadAnimations.Codec = p.OffloadAnimations.Folder .. ".codec"
p.OffloadAnimations.Interpolation = p.OffloadAnimations.Folder .. ".interpolation"
p.OffloadAnimations.Loader = p.OffloadAnimations.Folder .. ".loader"
p.OffloadAnimations.Player = p.OffloadAnimations.Folder .. ".player"
p.OffloadAnimations.LocalPlayer = p.OffloadAnimations.Folder .. ".localPlayer"
p.OffloadAnimations.Stream = p.OffloadAnimations.Folder .. ".stream"

p.RuzUtils = { Folder = p.APIFolder .. ".RuzsUtils"}
p.RuzUtils.API = p.RuzUtils.Folder .. ".API"
p.RuzUtils.CommandManager = p.RuzUtils.Folder .. ".commandManager"

config.OffloadAnimations = {
    paths = {
        dataDirectory = "offloadAnimations_Data/",
        manifestFile = "manifest.json"
    },

    data = {
        modelParts = {
            root = models.model.root,
            head = models.model.root.Head,
            body = models.model.root.Body,
            leftArm = models.model.root.LeftArm,
            rightArm = models.model.root.RightArm,
            leftLeg = models.model.root.LeftLeg,
            rightLeg = models.model.root.RightLeg,
        },

        defaultTypes = {},
    },

    CURRENT_ANIMATION_KEY = "OA_CurrentAnimation",
    TICKS_PER_SECOND = 20,
    LOG_PREFIX_JSON ='{"text":"[","color":"white"},{"text":"Offload","color":"gold"},{"text":"Animations","color":"yellow"}',
    MAX_BYTES_PER_SECOND = 800,
    PRECISION = 1000.0, 
}

for name, part in pairs(config.OffloadAnimations.data.modelParts) do
    config.OffloadAnimations.data.defaultTypes[name] = part:getParentType()
end
```

---

## API Functions

---

### Play Animation
`OffloadAnimations.playAnimation(animationName, role, speed)`

Plays a named animation by loading its data from the manifest, streaming it to all clients, and starting local playback.

#### **Parameters**
| Name | Type | Description |
|------|------|-------------|
| `animationName` | `string` | The key of the animation as defined in `manifest.json`. |
| `role` | `string?` | Which role to play (e.g., `"player1"`). Defaults to `"player1"`. |
| `speed` | `number?` | Playback speed multiplier. Defaults to `1.0`. |

#### **Returns**
None.

#### **Notes**
- Stops any existing animation on all clients.
- Logs an error if the manifest is not loaded.
- Logs an error if the animation cannot be found.

---

### Play Raw At
`OffloadAnimations.playRawAt(animData, startTime, role, speed, initiator)`

Plays a raw animation table at scheduled time. This function is mainly used for two player animations

#### **Parameters**
| Name | Type | Description |
|------|------|-------------|
| `animData` | `table` | Raw animation data (matching the JSON schema). |
| `startTime` | `number` | The world time the animation should begin at. |
| `role` | `string` | Which role in the animation to play. |
| `speed` | `number?` | Speed multiplier. Defaults to `1.0`. |
| `initiator` | `string?` | Name of the player who triggered the animation. |

#### **Returns**
None.

---

### Stop Animations 
`OffloadAnimations.stopAnimations()`

Stops animation playback locally.

#### **Returns**
None.

---

### Get All Animation Names 
`OffloadAnimations.getAllAnimationNames()`

Returns a sorted list of animation names found in the manifest.

#### **Returns**
`string[]` – A list of animation keys.  
Empty list if the Loader is unavailable.

---

### Get Animation 
`OffloadAnimations.getAnimation(animationName, role)`

Retrieves raw animation data for a specific animation and a specific role.

#### **Parameters**
| Name | Type | Description |
|------|------|-------------|
| `animationName` | `string` | The animation key. |
| `role` | `string?` | The role to return. |

#### **Returns**
`table?` – Animation data, or `nil` if not found.

---

### Get Animation With All Roles 
`OffloadAnimations.getAnimationWithAllRoles(animationName)`

Retrieves an animation table containing all roles data.

#### **Parameters**
| Name | Type | Description |
|------|------|-------------|
| `animationName` | `string` | The animation key. |

### **Returns**
`table?` – Animation data for all roles, or `nil` if not found.

---

### Stop Clients 
`pings.stopClients()`

Stops animations on all clients by calling `Player.stop()`.

#### **Returns**
None.

---

### Load Manifest 
`pings.loadManifests(map)`

Loads manifest part mappings, enabling streamed animations.

#### **Parameters**
| Name | Type | Description |
|------|------|-------------|
| `map` | `table` | The part mapping table from the Loader. |

#### **Returns**
None.

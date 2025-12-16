# JoinInAnimations

JoinInAnimations is an extension library built on top of [OffloadAnimations](https://github.com/Ruz-on-git/Ruz-s-Figura-Libs/tree/main/Libs/Offload%20Animations) that allows **two players to synchronize animations together**.

It uses [JustCommunicate](https://github.com/Ruz-on-git/Ruz-s-Figura-Libs/tree/main/Libs/Just%20Communicate) to send the animation data to your partner and then syncs a start time for different roles in an animation. The animations are played with the initiator being the anchor location.

If something is already explained in the [OffloadAnimations](https://github.com/Ruz-on-git/Ruz-s-Figura-Libs/tree/main/Libs/Offload%20Animations) documentation (model setup, animation extraction, manifests, roles), it will be referenced instead of repeated here.

---

## Index

- [Requirements](#requirements)
- [Installation](#installation)
- [Basic Setup](#basic-setup)
- [Preparing Animations](#preparing-animations)
- [Using Join In Animations](#using-join-in-animations)

---

## Requirements

JoinInAnimations requires all of the following:

- [OffloadAnimations](https://github.com/Ruz-on-git/Ruz-s-Figura-Libs/tree/main/Libs/Offload%20Animations)
- [JustCommunicate](https://github.com/Ruz-on-git/Ruz-s-Figura-Libs/tree/main/Libs/Just%20Communicate)
- [RuzUtils](https://github.com/Ruz-on-git/Ruz-s-Figura-Libs/tree/main/Libs/Ruz%20Utils)
- [ExtendedJson](https://github.com/Ruz-on-git/Ruz-s-Figura-Libs/blob/main/Libs/ExtendedJson.lua)
- [WhitelistMe](https://github.com/Ruz-on-git/Ruz-s-Figura-Libs/tree/main/Libs/Whitelist%20Me)

- A shared `config.lua` file defining module paths

Refer to the **OffloadAnimations Installation & Setup** section for:
- Basic avatar setup
- Model part mapping
- Animation extraction
- Manifest loading

---

## Installation
I would highly suggest looking at the example for how to setup an avatar as it will probaly do a better explanation than me.

Place the JoinInAnimations file in your APIs folder (or wherever defined in your config) with your other dependencies.

Example structure:
```
APIs/
 ├─ OffloadAnimations/
 ├─ JustCommunicate/
 ├─ RuzsUtils/
 ├─ ExtendedJson.lua
 ├─ JoinInAnimations.lua
 └─ WhitelistMe.lua
```

Then expose the API path in your `config.lua` (i would highly suggest using the config from the example folder):

```lua
p.JoinInAnimations = p.APIFolder .. ".JoinInAnimations"
```

---

## Basic Setup

Require JoinInAnimations in your main script or animation controller:

```lua
local cfg = require("config")
local JoinIn = require(cfg.paths.JoinInAnimations.API)
```

then run the init command

```lua
JoinIn.init()
```

This does the following:
- Initializes JustCommunicate under the `JoinInAnims` channel
- Registers required network listeners
- Marks your avatar as JoinIn-enabled

---

## Preparing Animations

Setting up animations for 2 player animations is very similar to how they are setup for the animations setup for OffloadAnimations, with the main difference being that you should addtionaly define the parts for the seccond role in the animation. 

You are able to name your roles for your animation however you want, with the default being player1 and player2. if no role is found when playing an animation it will defualt to player1.

---

## Using Join In Animations

### Sending a Request

To start a animation, call:

```lua
JoinIn.request(
    "OtherPlayer",   -- target player name
    "hug",           -- animation name
    "player1",          -- your role
    "player2"          -- their role
)
```

This sends a request to the target player.
The animation will **not** play immediately, instead waiting for some of the data to start streaming.

---

### Accepting Requests

Acceptance is automatic if:
- The sender is whitelisted (JustCommunicate)
- The target has JoinIn enabled

You can add your own UI or confirmation logic later if desired.

---

## Timeouts & Limits

- Request timeout: **200 ticks**
- Stream speed is limited by:
```
OffloadAnimations.MAX_BYTES_PER_SECOND
```

If a request times out or fails validation, it is automatically cleared.

---

## Common Issues

**Animation does not start**
- OffloadAnimations manifest not loaded

**Target not accepting**
- Target not whitelisted
- Target has JoinIn disabled


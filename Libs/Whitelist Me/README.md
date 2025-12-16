# WhitelistMe

Whitelist me is a simple script for Figura that allows for users to create whitelists to be used with other code.  

---

## Installation

Place this file in your APIs folder (or a custom location)

Have a config file in your main directory with a path link to where RuzUtils is
eg:
```lua
local p = config.paths

p.RuzUtils = { Folder = p.APIFolder .. ".RuzsUtils"}
p.RuzUtils.API = p.RuzUtils.Folder .. ".API"
p.RuzUtils.CommandManager = p.RuzUtils.Folder .. ".commandManager"

return config
```

---

## Usage

### 1. Create or retrieve a whitelist

Each whitelist is stored using its own config key:

```lua
local wl = WhitelistMe.get("myWhitelist")
```

If it exists, it loads saved data. If not, a new one is created.

---

### 2. Add a player

```lua
local result = wl:addToWhitelist("PlayerName or UUID")
print(result.message)
```

Returns:

```lua
{
    success = true/false,
    message = "..."
}
```

---

### 3. Remove a player

```lua
local result = wl:removeFromWhitelist("PlayerName or UUID")
print(result.message)
```

Fails if the whitelist is in `"*"` mode.

---

### 4. Change whitelist mode

Modes:

- `"*"` / `"all"` — allow everyone  
- `"none"` — allow no one (clears list)  

```lua
wl:setWhitelistMode("*")
wl:setWhitelistMode("none")
```

---

### 5. Check if a player is allowed

```lua
local allowed = wl:isAllowed(uuid)
if allowed then
    print("Player allowed!")
end
```

---

### 6. List all whitelisted players

```lua
for _, entry in ipairs(wl:getWhitelisted()) do
    print(entry)
end
```

Returns formatted entries like:

```
Username (uuid-here)
```

or

```
All players allowed (*)
```
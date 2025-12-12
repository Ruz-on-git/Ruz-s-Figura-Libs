---@class WhitelistMe
local WhitelistMe = { ActiveWhitelists = {} }

---@class WhitelistInstance
---@field name string The config save name
---@field whitelist table|string The data (table of UUIDs or "*" string)
local WhitelistInstance = {}
WhitelistInstance.__index = WhitelistInstance

---@type RuzUtilsAPI
local Utils

function WhitelistMe.init(utils)
    Utils = utils
end

---Retrieves or creates a named whitelist instance and loads saved data.
---@param name string The unique name for this whitelist (used for config saving).
---@return WhitelistInstance
function WhitelistMe.get(name)
    if not Utils then error("WhitelistMe.init(utils) must be called before .get()") end

    if WhitelistMe.ActiveWhitelists[name] then
        return WhitelistMe.ActiveWhitelists[name]
    end

    local self = setmetatable({
        name = name,
        whitelist = config:load(name) or {}
    }, WhitelistInstance)

    WhitelistMe.ActiveWhitelists[name] = self
    return self
end

---Internal helper to save state to disk.
function WhitelistInstance:save()
    config:save(self.name, self.whitelist)
end

---Adds a player to the whitelist.
---@param id string Name or UUID.
function WhitelistInstance:addToWhitelist(id)
    local target = Utils.findPlayer(id)
    if not target then return { success = false, message = "Player not found: " .. id } end

    local uuid, name = target:getUUID(), target:getName()
    if uuid == player:getUUID() then return { success = false, message = "Cannot add yourself." } end

    if type(self.whitelist) ~= "table" then self.whitelist = {} end

    if self.whitelist[uuid] then
        return { success = false, message = name .. " is already whitelisted." }
    end

    self.whitelist[uuid] = name
    self:save()
    return { success = true, message = "Added " .. name .. " to whitelist." }
end

---Removes a player from the whitelist.
---@param id string Name or UUID.
function WhitelistInstance:removeFromWhitelist(id)
    if self.whitelist == "*" then return { success = false, message = "Mode is '*'. Cannot remove individual." } end
    if type(self.whitelist) ~= "table" then self.whitelist = {} end

    local target = Utils.findPlayer(id)
    local uuidToRemove

    if target then
        uuidToRemove = target:getUUID()
    else
        --- @diagnostic disable-next-line
        for u, n in pairs(self.whitelist) do
            if n == id or u == id then
                uuidToRemove = u
                break
            end
        end
    end

    if uuidToRemove and self.whitelist[uuidToRemove] then
        local name = self.whitelist[uuidToRemove]
        self.whitelist[uuidToRemove] = nil
        self:save()
        return { success = true, message = "Removed " .. name .. " from whitelist." }
    end

    return { success = false, message = "Player '" .. id .. "' not found in whitelist." }
end

---Sets the global whitelist mode.
---@param mode string "*", "all", or "none"
function WhitelistInstance:setWhitelistMode(mode)
    local m = (mode or ""):lower()
    
    if m == "*" or m == "all" then
        self.whitelist = "*"
        self:save()
        return { success = true, message = "Whitelist set to allow ALL (*)." }
    elseif m == "none" then
        self.whitelist = {}
        self:save()
        return { success = true, message = "Whitelist cleared (None allowed)." }
    end

    return { success = false, message = "Unknown mode: " .. mode }
end

---Checks if a UUID is allowed.
function WhitelistInstance:isAllowed(uuid)
    if self.whitelist == "*" then return true end
    return type(self.whitelist) == "table" and self.whitelist[uuid] ~= nil
end

---Gets a formatted list of allowed players.
function WhitelistInstance:getWhitelisted()
    if self.whitelist == "*" then return { "All players allowed (*)" } end
    if type(self.whitelist) ~= "table" then return {} end

    local list = {}
    --- @diagnostic disable-next-line
    for uuid, name in pairs(self.whitelist) do
        table.insert(list, string.format("%s (%s)", name, uuid))
    end
    return list
end

return WhitelistMe
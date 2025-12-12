---@meta

local utilsPath = "APIs.RuzsUtils."

---@class RuzUtilsAPI
---@field tasks table<number, {id:number, endTime:number, func:function, args:table}>
---@field taskId number
local RuzsUtils = { tasks = {}, taskId = 0 }

RuzsUtils.CommandManager = require(utilsPath .. "commandManager")
RuzsUtils.CommandManager.new(RuzsUtils)

local LOG_PREFIX = '[{"text":"[","color":"white"},{"text":"Ruzs","color":"red"},{"text":"Utils","color":"blue"}]'

--#region Scheduler
events.TICK:register(function()
    if #RuzsUtils.tasks == 0 then return end
    --- @diagnostic disable-next-line
    local time = world:getTime()
    for i = #RuzsUtils.tasks, 1, -1 do
        local task = RuzsUtils.tasks[i]
        if time >= task.endTime then
            task.func(table.unpack(task.args))
            table.remove(RuzsUtils.tasks, i)
        end
    end
end)

---Schedules a function to be executed after a specified number of game ticks.
---@param ticks number The delay in ticks (20 ticks = 1 second).
---@param func function The function to execute.
---@param ... any Arguments to pass to the function.
---@return number taskId The unique ID of the scheduled task.
function RuzsUtils.runAfterDelay(ticks, func, ...)
    if type(func) ~= "function" then print("Error: runAfterDelay expects function") return nil end
    RuzsUtils.taskId = RuzsUtils.taskId + 1
    table.insert(RuzsUtils.tasks, {
        id = RuzsUtils.taskId,
        --- @diagnostic disable-next-line
        endTime = world:getTime() + (ticks or 1),
        func = func,
        args = {...}
    })
    return RuzsUtils.taskId
end

---Cancels a pending scheduled task by its ID.
---@param id number The task ID returned by runAfterDelay.
---@return boolean success True if the task was found and removed, false otherwise.
function RuzsUtils.cancelTask(id)
    for i, task in ipairs(RuzsUtils.tasks) do
        if task.id == id then
            table.remove(RuzsUtils.tasks, i)
            return true
        end
    end
    return false
end

--#endregion
--#region Logging
---Logs a formatted JSON message to the chat.
---@param msg any The message content (converted to string).
---@param color string|nil The text color (default: white).
---@param prefix string|nil A raw JSON string for the prefix (default: RuzsUtils standard prefix).
---@param submodule string|nil An optional submodule name to display after the prefix.
function RuzsUtils.log(msg, color, prefix, submodule)
    local sub = submodule and string.format(',{"text":"/","color":"white"},{"text":"%s","color":"green"}', submodule) or ""
    local json = string.format('[%s%s,{"text":"]: %s\\n","color":"%s"}]', 
        prefix or LOG_PREFIX, sub, tostring(msg):gsub('"', '\\"'), color or "white")
    printJson(json)
end

--#endregion
--#region Entity & Player Utils

---Checks if a UUID corresponds to a valid avatar in the world.
---@param uuid string The UUID to check.
---@return boolean valid True if the avatar variables exist for this UUID.
function RuzsUtils.isValidUUID(uuid)
    return world.avatarVars()[uuid] ~= nil
end

---Finds a player entity by UUID if they are loaded.
---@param uuid string The UUID of the player.
---@return Player|nil player The player entity or nil if not found.
function RuzsUtils.findPlayerFromUUID(uuid)
    --- @diagnostic disable-next-line
    return RuzsUtils.isValidUUID(uuid) and world.getEntity(uuid) or nil
end

---Finds a player by Username or UUID.
---@param id string The username or UUID.
---@return Player|nil player The player entity or nil.
function RuzsUtils.findPlayer(id)
    return world.getPlayers()[id] or RuzsUtils.findPlayerFromUUID(id)
end

---Gets the entity the client player is currently looking at within the specified range.
---@param range number|nil the range of the raycast (default 20).
---@return Entity|nil entity The target entity or nil if looking at air/blocks.
function RuzsUtils.getLookingAtEntity(range)
    local pos = player:getPos():add(0, player:getEyeHeight(), 0)
    --- @diagnostic disable-next-line
    return raycast:entity(pos, pos + (player:getLookDir() * (range or 20)), function(e) return e ~= player end)
end

--#endregion
--#region File IO

---Reads the content of an internal resource file.
---@param path string The path to the resource.
---@return string|nil content The file content, or nil if not found.
function RuzsUtils.readResource(path)
    local stream = resources:get(path)
    if not stream then return RuzsUtils.log("Resource missing: " .. tostring(path), "red", LOG_PREFIX) end
    
    local chunks = {}
    while true do
        local b = stream:read()
        if not b then break end
        table.insert(chunks, string.char(b))
    end
    return table.concat(chunks)
end

---Reads the content of an external file (requires File API permission).
---@param path string The path to the file.
---@return string|nil content The file content, or nil on failure.
function RuzsUtils.readDataFile(path)
    if not file:allowed() then return RuzsUtils.log("No file access.", "red", "FileSystem") end
    if not file:exists(path) then return RuzsUtils.log("File missing: " .. path, "yellow", "FileSystem") end

    local ok, content = pcall(file.readString, file, path, "UTF-8")
    if not ok then RuzsUtils.log("Read failed: " .. tostring(content), "red", "FileSystem") end
    return ok and content or nil
end

--#endregion

return RuzsUtils
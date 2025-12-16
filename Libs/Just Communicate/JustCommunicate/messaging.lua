---@meta

---@class JustCommunicateMessaging
local Messaging = {}

---@type RuzUtilsAPI
local Utils
---@type ExtendedJson
local JSON
---@type JCConfig
local Config
---@type WhitelistInstance
local Whitelist

local listeners = {}
local buffer = {}
local history = {}

function Messaging.init(utils, config, extendedJson, whitelist)
    Utils, Config, JSON, Whitelist = utils, config, extendedJson, whitelist

    events.CHAT_RECEIVE_MESSAGE:register(function(msg)
        return Messaging.receive(msg)
    end)
end

---@param type string
---@param callback function
function Messaging.addListener(type, callback)
    if type and callback then listeners[type] = callback end
end

function Messaging.removeListener(type)
    listeners[type] = nil
end

local function log(msg, type)
    Utils.log(msg, type or Config.LOGTYPES.LOG, Config.LOG_PREFIX_JSON)
end

local function processBuffer(id)
    local data = buffer[id]
    if not data then return end

    local raw = table.concat(data.parts)
    
    if data.isJson then
        local ok, decoded = pcall(JSON.decode, raw)
        if not ok then return log("JSON Decode Error: " .. tostring(decoded), Config.LOGTYPES.ERROR) end
        raw = decoded
    end

     if listeners[data.type] then
        local ok, err = pcall(listeners[data.type], raw, data.sender)
        if not ok then
            log("Listener Error ("..data.type.."): " .. tostring(err), Config.LOGTYPES.ERROR)
        end
    else
        log("No listener for type: " .. tostring(data.type), Config.LOGTYPES.WARNING)
    end

    buffer[id] = nil
    history[id] = true
end

---Sends a data payload to a specific player.
---@param messageType string Message type ID.
---@param data string|table Data to send.
---@param targetName string Player name.
---@param delay? number Ticks between chunks (default 2).
function Messaging.send(messageType, data, targetName, delay)
    if not (messageType and targetName) then return { success = false, message = "Missing type or target." } end
    
    local target = Utils.findPlayer(targetName)
    if not target then return { success = false, message = "Target offline/not found." } end
	
    local isTable = (type(data) == "table")
    local content = isTable and JSON.encode(data) or tostring(data)
    
    local limit = Config.MAX_PAYLOAD_LENGTH
    local total = math.ceil(#content / limit)
    local id = math.random(1, 9999999)
    local currentDelay = 0

    for i = 1, total do
        local chunk = content:sub(1 + (i - 1) * limit, i * limit)
        
        local packet = JSON.encode({
            type = messageType, id = id, part = i, total = total,
            content = chunk, target = targetName, sender = player:getName(),
            iscustomJson = isTable
        })

        local safePacket = packet:gsub("\\", "\\\\"):gsub('"', '\\"')
        local cmd = string.format('/tellraw %s {"text":"%s%s"}', targetName, Config.MARKER_PREFIX, safePacket)

        Utils.runAfterDelay(currentDelay, function() host:sendChatCommand(cmd) end)
        currentDelay = currentDelay + (delay or 2)
    end

    return { success = true, message = string.format("Sent %d parts to %s.", total, targetName) }
end

---Internal handler for incoming chat messages.
---@param raw string
---@return boolean|nil true to cancel message, nil to pass through.
function Messaging.receive(raw)
    local prefix = Config.MARKER_PREFIX
    if not raw:find(prefix, 1, true) then return nil end

    local jsonStr = raw:sub(#prefix + 1)
    local ok, pkg = pcall(JSON.decode, jsonStr)

    if not (ok and type(pkg) == "table") then return false end
    if pkg.target ~= player:getName() or history[pkg.id] then return false end

    local sender = Utils.findPlayer(pkg.sender)
    if not (sender and (sender == player or Whitelist:isAllowed(sender:getUUID()))) then
        return false
    end

    local id = pkg.id
    if not buffer[id] then
        buffer[id] = { 
            parts = {}, count = 0, total = pkg.total, 
            type = pkg.type, sender = pkg.sender, isJson = pkg.iscustomJson 
        }
    end

    if not buffer[id].parts[pkg.part] then
        buffer[id].parts[pkg.part] = pkg.content
        buffer[id].count = buffer[id].count + 1
    end

    if buffer[id].count >= buffer[id].total then
        processBuffer(id)
    end

    return false
end

return Messaging
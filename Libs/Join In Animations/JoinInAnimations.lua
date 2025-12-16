local cfg = require("config")
---@type RuzUtilsAPI
local Utils = require(cfg.paths.RuzUtils.API)
---@type JustCommunicate
local JC = require(cfg.paths.JustCommunicate.API)
---@type OffloadAnimations
local OA = require(cfg.paths.OffloadAnimations.API)

---@class JoinInAnimations
local JoinIn = {}

local TIMEOUT = 200
local LOG_PREFIX = cfg.JoinInAnimations.LOG_PREFIX_JSON
local STREAM_BYTES_PER_SEC = cfg.OffloadAnimations.MAX_BYTES_PER_SECOND
local STREAM_BUFFER = 20 

---@class JIA.PendingRequest
---@field anim string The name of the animation identifier
---@field myRole string The role the local player will take
---@field theirRole string The role the target player will take
---@field taskId integer|function The ID of the timeout task

---@type table<string, JIA.PendingRequest>
local pending = {}

---Clears a pending request for a specific player and cancels the timeout task.
---@param name string The name of the player to clear.
---@return JIA.PendingRequest|nil req The request that was cleared, or nil if none existed.
local function clearRequest(name)
    if pending[name] and pending[name].taskId then
        ---@diagnostic disable-next-line
        Utils.cancelTask(pending[name].taskId)
    end
    local req = pending[name]
    pending[name] = nil
    return req
end

---Calculates the future world time to start the animation.
---@param animData table The animation data containing chunks.
---@return number startTime The calculated world time (in ticks) to start playing.
local function calculateSyncTime(animData)
    local totalBytes = 0
    
    if animData.chunks then
        for _, b64 in ipairs(animData.chunks) do
            totalBytes = totalBytes + math.floor((#b64 * 3) / 4)
        end
    end

    local ticksNeeded = math.ceil(totalBytes / STREAM_BYTES_PER_SEC) * 20
    
    ---@diagnostic disable-next-line
    return world:getTime() + ticksNeeded + STREAM_BUFFER
end

---Handler for receiving a request (JIA_REQ).
---Checks whitelist and sends acceptance if valid.
---@param _ table Payload (unused).
---@param senderName string The username of the requester.
local function onRequest(_, senderName)
    local sender = Utils.findPlayer(senderName)
    if sender and JC.isWhitelisted(sender:getUUID()) then
        JC.sendMessage("JIA_ACC", {}, senderName, 0)
    end
end

---Handler for receiving acceptance (JIA_ACC).
---Calculates sync time, sends animation data to target, and plays local animation.
---@param _ table Payload (unused).
---@param senderName string The username of the player who accepted.
local function onAccept(_, senderName)
    local req = clearRequest(senderName)
    if not req then return end

    local myData = OA.getAnimation(req.anim, req.myRole)
    local theirData = OA.getAnimation(req.anim, req.theirRole)
    theirData.events = nil

    if not (myData and theirData) then
        return Utils.log("Failed to load animation data for acceptance.", "red", LOG_PREFIX)
    end

    local startTime = calculateSyncTime(theirData)

    JC.sendMessage("JIA_PLAY", { 
        data = theirData, 
        time = startTime, 
        role = req.theirRole 
    }, senderName, 2)

    ---@diagnostic disable-next-line: undefined-global
    OA.playRawAt(myData, startTime, req.myRole, 1.0, player:getName())
end

---Handler for the play command (JIA_PLAY).
---Receives animation data and schedules it to play at the synchronized time.
---@param payload {data: table, time: number, role: string}
---@param senderName string
local function onPlay(payload, senderName)
    if payload.data and payload.time then
        OA.playRawAt(payload.data, payload.time, payload.role, 1.0, senderName)
    end
end

---Initiates a synchronized animation request with a target player.
---@param targetName string The name of the player to sync with.
---@param anim string The animation identifier to load.
---@param myRole string The role identifier for the local player.
---@param theirRole string The role identifier for the target player.
function JoinIn.request(targetName, anim, myRole, theirRole)
    if not OA.manafestLoaded then return Utils.log("Please wait for the manefests to load before trying to request an animations.", "yellow", LOG_PREFIX) end
    if not JC.whitelist then return Utils.log("Please initialise just communicate before trying to play an animations.", "red", LOG_PREFIX) end

    local target = Utils.findPlayer(targetName)
    if not target then return Utils.log("Target '" .. targetName .. "' not found.", "red", LOG_PREFIX) end
    if not target:getVariable("JIA_ENABLED") then return Utils.log("Target '" .. targetName .. "' has JIA disabled.", "red", LOG_PREFIX) end
    if not (OA.getAnimation(anim, myRole) and OA.getAnimation(anim, theirRole)) then
        return Utils.log("Roles '" .. myRole .. "/" .. theirRole .. "' missing locally.", "red", LOG_PREFIX)
    end

    clearRequest(targetName)

    pending[targetName] = {
        anim = anim, myRole = myRole, theirRole = theirRole,
        taskId = Utils.runAfterDelay(TIMEOUT, function()
            if clearRequest(targetName) then
                Utils.log("Request to " .. targetName .. " timed out.", "yellow", LOG_PREFIX)
            end
        end)
    }

    JC.sendMessage("JIA_REQ", { anim = anim }, targetName, 0)
    Utils.log("Request sent to " .. targetName, "gray", LOG_PREFIX)
end

function JoinIn.init()
    JC.init("JoinInAnims")
    ---@diagnostic disable-next-line: undefined-global
    avatar:store("JIA_ENABLED", true)
    
    JC.addListener("JIA_REQ", onRequest)
    JC.addListener("JIA_ACC", onAccept)
    JC.addListener("JIA_PLAY", onPlay)
end

return JoinIn
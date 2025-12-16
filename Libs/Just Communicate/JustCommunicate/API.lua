local mainConfig = require("config")
local paths = mainConfig.paths
local localConfig = mainConfig.JustCommunicate

---@type RuzUtilsAPI
local Utils = require(paths.RuzUtils.API)
---@type ExtendedJson
local ExtendedJson = require(paths.ExtendedJson)
---@type WhitelistMe
local Whitelist = require(paths.WhitelistMe)

---@type JustCommunicateCommands
local Commands = require(paths.JustCommunicate.Commands)
---@type JustCommunicateMessaging
local Messaging = require(paths.JustCommunicate.Messaging)

---@class JustCommunicate
---@field whitelist WhitelistInstance
local JustCommunicate = {}

JustCommunicate.sendMessage = Messaging.send
JustCommunicate.addListener = Messaging.addListener
JustCommunicate.removeListener = Messaging.removeListener

---@param value boolean
function pings.JC_STATUS_CHANGED(value)
    avatar:store("JC_ENABLED", value)
end

function JustCommunicate.setWhitelist(...) return JustCommunicate.whitelist:setWhitelistMode(...) end
function JustCommunicate.addToWhitelist(...) return JustCommunicate.whitelist:addToWhitelist(...) end
function JustCommunicate.removeFromWhitelist(...) return JustCommunicate.whitelist:removeFromWhitelist(...) end
function JustCommunicate.isWhitelisted(...) return JustCommunicate.whitelist:isAllowed(...) end

---@param whitelistName string The name of the whitelist configuration to load.
function JustCommunicate.init(whitelistName)
    JustCommunicate.whitelist = Whitelist.get(whitelistName)
    Commands.init(localConfig, Utils, JustCommunicate.whitelist)
    Messaging.init(Utils, localConfig, ExtendedJson, JustCommunicate.whitelist)

    events.ENTITY_INIT:register(function()
        avatar:store("JC_ENABLED", true)
        if not host:isHost() then return end

        JustCommunicate.whitelist:setWhitelistMode("*")
        Utils.log("JustCommunicate initializing...", localConfig.LOGTYPES.LOG, localConfig.LOG_PREFIX_JSON)

        local timeoutId

        local function onInitSuccess()
            Utils.cancelTask(timeoutId)
            Utils.log("Self-check successful. Just Communicate is ready to use", localConfig.LOGTYPES.LOG, localConfig.LOG_PREFIX_JSON)
            JustCommunicate.removeListener("initMessage")
        end

        local function onInitFail()
            Utils.log("Initialization FAILED - Timeout.", localConfig.LOGTYPES.ERROR, localConfig.LOG_PREFIX_JSON)
            JustCommunicate.removeListener("initMessage")
            pings.JC_STATUS_CHANGED(false)
        end

        JustCommunicate.addListener("initMessage", onInitSuccess)
        Messaging.send("initMessage", "Startup complete!", player:getName(), 0)
        
        timeoutId = Utils.runAfterDelay(10, onInitFail)
    end)
end

return JustCommunicate
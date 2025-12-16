---@class OffloadAnimations
--- Allows the offloading of animations to json files which can then be streamed to other clients though pings.
--- Also alows for animations to have camera movements defined in blockbench.
local OffloadAnimations = {}

local mainConfig = require("config")
--- @type ConfigPaths
local paths = mainConfig.paths
local localPaths = paths.OffloadAnimations

---@type OAConfig
local LocalConfig = mainConfig.OffloadAnimations

---@type RuzUtilsAPI
local RuzUtils = require(paths.RuzUtils.API)

---@type ExtendedJson
local ExtendedJson = require(paths.ExtendedJson)

---@type InterpolationModule
local Interpolation = require(localPaths.Interpolation)

---@type CodecModule
local Codec = require(localPaths.Codec)

---@type AnimationLoaderModule
local Loader = require(localPaths.Loader)
Loader.init(RuzUtils, ExtendedJson, LocalConfig)

---@type AnimationStreamModule
local Stream = require(localPaths.Stream)
Stream.init(Codec, LocalConfig)

---@type AnimationPlayerModule
local Player = require(localPaths.Player)
Player.init(Interpolation, LocalConfig, Stream, RuzUtils)

---@type LocalPlayerModule
local LocalPlayer = require(localPaths.LocalPlayer)
LocalPlayer.init(RuzUtils)

OffloadAnimations.manafestLoaded = false

--- Loads an animation by name, stops any currently playing animation, and begins streaming the new data to all players.
--- @param animationName string The key name of the animation (from manifest.json).
--- @param role string|nil The role to play (defaults to "player1").
--- @param speed number|nil Playback speed multiplier (defaults to 1.0).
function OffloadAnimations.playAnimation(animationName, role, speed)
    if not OffloadAnimations.manafestLoaded then
        RuzUtils.log("Please wait for the manafest to load before trying to play an animation", "yellow", LocalConfig.LOG_PREFIX_JSON)
        return
    end

    local animData = Loader.getAnimation(animationName, role)
    if not animData then
        RuzUtils.log("OffloadAnimations Error: Could not load animation data for '" .. tostring(animationName) .. "'", "red", LocalConfig.LOG_PREFIX_JSON)
        return
    end

    pings.stopClients()

    local startTime = Stream.sendAnimation(animData, speed, true, player:getName())
    LocalPlayer.playLocalAnimations(animData, startTime, role)
end

--- Plays raw animation table data at a specifically scheduled time.
--- @param animData table The raw animation data.
--- @param startTime number The future world time to start playing.
--- @param role string The role to play.
--- @param speed number|nil Speed multiplier.
--- @param initiator string|nil The name of the initator
function OffloadAnimations.playRawAt(animData, startTime, role, speed, initiator)
    if not OffloadAnimations.manafestLoaded then
        RuzUtils.log("Please wait for the manafest to load before trying to play an animation", "yellow", LocalConfig.LOG_PREFIX_JSON)
        return
    end

    pings.stopClients()
    
    Stream.sendAnimation(animData, speed, true, initiator)
    LocalPlayer.playLocalAnimations(animData, startTime, role, initiator)
end

--- Stops the current animation on the Host and sends a signal to stop all Clients.
function OffloadAnimations.stopAnimations()
    LocalPlayer.stop()
    pings.stopClients()
end

--- Triggers the Player module to stop running for all clients.
function pings.stopClients()
    Player.stop()
end

--- Returns a sorted list of all available animation names found in the manifest.
--- @return string[]
function OffloadAnimations.getAllAnimationNames()
    return Loader and Loader.getAllAnimationNames() or {}
end

--- Retrieves the raw data for a specific animation and role.
--- @param animationName string
--- @param role string|nil
--- @return table|nil
function OffloadAnimations.getAnimation(animationName, role)
    return Loader and Loader.getAnimation(animationName, role) or nil
end

--- Retrieves the raw data for an animation containing all role streams.
--- @param animationName string
--- @return table|nil
function OffloadAnimations.getAnimationWithAllRoles(animationName)
    return Loader and Loader.getAnimationWithAllRoles(animationName) or nil
end

events.RENDER:register(function(delta)
    Player.update(delta)
    Stream.update(delta)

    if host:isHost() then 
        LocalPlayer.update(delta) 
    end
end)

events.ENTITY_INIT:register(function ()
    function pings.loadManifest(map)
        if not map or next(map) == nil then
            return RuzUtils.log("Manifest has failed to load. Is it missing?", "red", LocalConfig.LOG_PREFIX_JSON)
        end

        Stream.updatePartMap(map)
        OffloadAnimations.manafestLoaded = true

        RuzUtils.log("Manifest has been loaded, animations are ready to play.", "white", LocalConfig.LOG_PREFIX_JSON)
    end

    ---Needs to wait for the avatar to upload
    RuzUtils.log("Waiting for manifest to load...", "white", LocalConfig.LOG_PREFIX_JSON)
    RuzUtils.runAfterDelay(60, function()
        pings.loadManifest(Loader.getManifestIDs())
    end)
end)

return OffloadAnimations
---@class AnimationLoaderModule
local AnimationLoader = {}
AnimationLoader.__index = AnimationLoader

---@type RuzUtilsAPI
local RuzUtils
---@type ExtendedJson
local ExtendedJson
--- @type OAConfig
local OAConfig

local memoryCache = {}
local importedRawCache = {}
local animationManifest = {anims = {}, neededParts = {}, ids = {}}

local function _verifyModelParts()
    local missing = {}
    for part, anims in pairs(animationManifest.neededParts or {}) do
        if not OAConfig.data.modelParts[part] then
            local n = #anims
            local list = table.concat({table.unpack(anims, 1, math.min(n, 3))}, ", ")
            local suffix = n > 3 and (" and " .. (n - 3) .. " others") or ""
            missing[#missing+1] = string.format(" • %s → [%s%s]", part, list, suffix)
        end
    end

    if #missing > 0 then
        local msg = "Missing modelParts in config:\n" .. table.concat(missing, "\n") .. 
                    "\nThese parts will not animate. Please update OAConfig.data.modelParts."
        RuzUtils.log(msg, "yellow", OAConfig.LOG_PREFIX_JSON, "loader")
    end
end

local function _loadManifest()
    local path = OAConfig.paths.dataDirectory .. OAConfig.paths.manifestFile

    local str = RuzUtils.readDataFile(path)
    if not str then return end
    
    local success, data = pcall(ExtendedJson.decode, str)
    if success and type(data) == "table" then
        animationManifest = data
        _verifyModelParts() 
    end
end

--- Retrieves the raw JSON data for an animation by name.
--- @param name string The name of the animation (key in manifest).
--- @return table|nil result The raw decoded JSON table, or nil if not found/failed to load.
local function _getRawData(name)
    local hash = animationManifest.anims[name]
    if not hash then return nil end

    if importedRawCache[hash] then return importedRawCache[hash] end

    local content = RuzUtils.readDataFile(OAConfig.paths.dataDirectory .. hash .. ".json")
    if not content then return nil end

    local success, data = pcall(ExtendedJson.decode, content)
    if not success or type(data) ~= "table" then return nil end

    importedRawCache[hash] = data
    return data
end

--- Fetches, constructs, and caches an usable animation object.
--- @param name string The animation name.
--- @param cacheKey string The unique key for the memory cache.
--- @param builderFn function A function that takes raw data and returns specific fields (streams/chunks) for the object.
--- @return table|nil result The constructed animation object with common metadata, or nil if loading failed.
local function _resolve(name, cacheKey, builderFn)
    if memoryCache[cacheKey] then return memoryCache[cacheKey] end

    local raw = _getRawData(name)
    if not raw then return nil end

    local obj = builderFn(raw)
    if obj then 
        obj.name = raw.name
        obj.hash = raw.hash
        obj.duration = raw.duration
        obj.settings = raw.settings
        obj.cameras = raw.cameras
        obj.events = raw.events
        
        memoryCache[cacheKey] = obj
    end
    return obj
end

--- @param importedUtils RuzUtilsAPI
--- @param importedJson ExtendedJson
--- @param localConfig OAConfig
function AnimationLoader.init(importedUtils, importedJson, localConfig)   
    RuzUtils, ExtendedJson, OAConfig = importedUtils, importedJson, localConfig
    if host:isHost() then _loadManifest() end
end

--- Retrieves an animation object for a role.
--- @param name string The name of the animation.
--- @param role string|nil The role identifier (defaults to "player1").
--- @return table|nil result An object containing the 'chunks' specific to the role, or nil if not found.
function AnimationLoader.getAnimation(name, role)
    role = role or "player1"
    return _resolve(name, name .. "_" .. role, function(raw)
        local stream = raw.streams and raw.streams[role]
        return stream and { chunks = stream } or nil
    end)
end

--- Retrieves an animation object containing data for all roles.
--- @param name string The name of the animation.
--- @return table|nil result An object containing 'streams' for all roles and the full 'serializableData'.
function AnimationLoader.getAnimationWithAllRoles(name)
    return _resolve(name, name .. "_all", function(raw)
        return {
            streams = raw.streams,
            serializableData = raw
        }
    end)
end

--- Returns a sorted list of all available animation names found in the manifest.
--- @return string[] result An alphabetical list of animation names.
function AnimationLoader.getAllAnimationNames()
    local names = {}
    for name in pairs(animationManifest.anims) do
        names[#names+1] = name
    end
    table.sort(names)
    return names
end

--- Returns the ID map from the manifest { "Head"=1, "Body"=2 }
function AnimationLoader.getManifestIDs()
    return animationManifest.ids
end

return AnimationLoader
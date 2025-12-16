---@class LocalPlayerModule
local localPlayer = {}

---@type RuzUtilsAPI
local RuzUtils

local compiledEvents = {}
local activeEvents = {}
local movementKeybinds = {}
local unlockTaskID = nil

local state = {
    isLocked = false,
    cameraData = nil,
    cameraRole = "shared",
    anim = { 
        hash = nil, 
        startTime = 0, 
        duration = 0, 
        startYaw = 0,
        initiatorName = nil,
        origin = nil,
        capturedOrigin = false
    }
}

local function _resetCamera()
    renderer:offsetCameraPivot(nil)
    renderer:setCameraRot(nil)
end

local function _vec3(t)
    return t and vec(t[1], t[2], t[3]) or vec(0, 0, 0)
end

--- Interpolates a channel value at a specific tick.
--- @param keyframes table List of keyframes.
--- @param tick number Current animation time.
--- @return Vector3 result The interpolated position/rotation.
local function _solveChannel(keyframes, tick)
    if not keyframes or #keyframes == 0 then return vec(0,0,0) end

    local kf = keyframes[1]
    local lastKf = keyframes[#keyframes]

    if tick >= lastKf.tick + lastKf.duration then
        return _vec3(lastKf.value) + _vec3(lastKf.delta)
    end

    for i = 1, #keyframes do
        local frame = keyframes[i]
        if tick >= frame.tick and tick < (frame.tick + frame.duration) then 
            kf = frame 
            break 
        end
    end

    if kf.duration <= 0 then return _vec3(kf.value) end

    local t = math.clamp((tick - kf.tick) / kf.duration, 0, 1)
    local factor = t 
    
    if kf.interp ~= 1 then
        factor = t < 0.5 and 4 * t * t * t or 1 - math.pow(-2 * t + 2, 3) / 2
    end
    
    return _vec3(kf.value) + (_vec3(kf.delta) * factor)
end

local function _isCamActive(timeline, tick)
    if not timeline then return true end
    
    local active = false
    for _, pt in ipairs(timeline) do
        if tick >= pt.tick then active = pt.active else break end
    end
    return active
end

--- @param utils RuzUtilsAPI
function localPlayer.init(utils)
    RuzUtils = utils
    
    local function checkLock() return state.isLocked end
    local keys = {"key.forward", "key.back", "key.left", "key.right", "key.jump", "key.sneak", "key.sprint"}
    for _, id in ipairs(keys) do
        movementKeybinds[#movementKeybinds+1] = keybinds:fromVanilla(id):onPress(checkLock)
    end
end

--- Prepares the local client for animation
--- @param data table The data for the animation
---@param startTime number The time the animation should start
---@param role string The role of the local player
---@param initiatorName string|nil The person who started the animation
function localPlayer.playLocalAnimations(data, startTime, role, initiatorName)
    localPlayer.stop()

    state.anim = {
        hash = data.hash,
        startTime = startTime,
        duration = data.duration,
        startYaw = 0,
        initiatorName = initiatorName,
        origin = nil,
        capturedOrigin = false
    }

    if data.settings.useCamera and data.cameras and next(data.cameras) then
        state.cameraData = data.cameras
        state.cameraRole = role
        
        if not renderer:isFirstPerson() then 
            host:actionbar("§cThis animation is best viewed in first person mode.") 
        end
    end

    if data.events and #data.events > 0 then
        if not compiledEvents[data.hash] then
            compiledEvents[data.hash] = {}
            for _, ev in ipairs(data.events) do
                local fn, err = load(ev.script, "anim_event", "t")
                if fn then
                    table.insert(compiledEvents[data.hash], { tick = ev.tick, fn = fn })
                else
                    RuzUtils.log("Event compile error:" .. err, "red")
                end
            end
        end

        activeEvents[data.hash] = {}
        for i, ev in ipairs(compiledEvents[data.hash]) do
            activeEvents[data.hash][i] = { tick = ev.tick, fn = ev.fn, fired = false }
        end
    end

    if data.settings.lockMovement then
        state.isLocked = true
        --- @diagnostic disable-next-line
        local delay = (startTime - world:getTime()) + data.duration
        unlockTaskID = RuzUtils.runAfterDelay(delay, localPlayer.stop)
    end
end

--- Stops any local animation handling
function localPlayer.stop()
    state.isLocked = false
    state.cameraData = nil
    state.anim.hash = nil
    
    if unlockTaskID then
        RuzUtils.cancelTask(unlockTaskID)
        unlockTaskID = nil
    end

    _resetCamera()
end

--- Runs the functions in the animation
function localPlayer.runEventTick(animHash, startTime, duration)
    local events = activeEvents[animHash]
    if not events then return end

    --- @diagnostic disable-next-line
    local elapsed = world:getTime() - startTime
    if elapsed > duration then
        activeEvents[animHash] = nil
        return
    end

    for _, ev in ipairs(events) do
        if not ev.fired and elapsed >= ev.tick then
            ev.fired = true
            pcall(ev.fn)
        end
    end
end

--- Runs the camera movements in the animation
function localPlayer.runCameraTick(delta)
    if not state.cameraData or not renderer:isFirstPerson() then
        if state.cameraData then _resetCamera() end
        return
    end

    local time = world.getTime(delta) - state.anim.startTime
    
    if time >= 0 and not state.anim.capturedOrigin then
        local initiator = RuzUtils.findPlayer(state.anim.initiatorName) or player
        state.anim.origin = initiator:getPos(delta)
        state.anim.startYaw = initiator:getBodyYaw(delta)
        state.anim.capturedOrigin = true
    end

    if time < 0 or time > state.anim.duration then return end

    local roleCam = state.cameraData[state.cameraRole]
    local sharedCam = state.cameraData["shared"]

    local activeCam = nil
    if roleCam and _isCamActive(roleCam.timeline, time) then
        activeCam = roleCam
    elseif sharedCam and _isCamActive(sharedCam.timeline, time) then
        activeCam = sharedCam
    end

    if not activeCam then
        _resetCamera()
        models.model:setVisible(false)
        return
    end
    models.model:setVisible(true)

    models.model:setParentType("World")
    
    local pos = _solveChannel(activeCam.position, time)
    local animOffset = vec(-pos.x/16, (pos.y/16) - 1.62, -pos.z/16)

    if state.anim.startYaw ~= 0 then
        animOffset = matrices.mat4():rotate(0, -state.anim.startYaw, 0):apply(animOffset)
    end

    local worldOffset = state.anim.origin - player:getPos(delta)

    local rot = _solveChannel(activeCam.rotation, time)
    local finalRot = vec(rot.x, rot.y + state.anim.startYaw, rot.z)

    renderer:offsetCameraPivot(animOffset + worldOffset)
    renderer:setCameraRot(finalRot)
end

function localPlayer.update(delta)
    if not state.anim.hash then return end

    localPlayer.runEventTick(state.anim.hash, state.anim.startTime, state.anim.duration)
    localPlayer.runCameraTick(delta)
end

return localPlayer
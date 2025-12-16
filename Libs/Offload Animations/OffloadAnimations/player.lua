---@class AnimationPlayerModule
local AnimationPlayer = {}

-- Dependencies
local Interpolation, LocalConfig, StreamManager, RuzUtils

-- Local constants for speed
local INTERP = { LINEAR = 1, CATMULL = 2, BEZIER = 3 }

---@class AnimationState
---@field transforms table<string|table, table> Map of parts to channel timelines.
---@field duration number Total duration in ticks.
---@field startTime number World time start tick.
---@field speed number Playback speed multiplier.
---@field events table[] List of event objects.
---@field eventsFired boolean[] helper to track fired events.
---@field overrideVanilla boolean Whether vanilla parts are hidden.
---@field readContext table|nil Decoding context for stream reader.
---@field onComplete function|nil Optional callback to run when the animation finishes.
AnimationPlayer.activeState = nil

--- Toggles visibility of vanilla armor and reparents custom parts.
--- @param hideVanilla boolean If true, hide armor/parent to World. If false, reset.
local function _setVanillaState(hideVanilla)
    vanilla_model.ARMOR:setVisible(not hideVanilla) 
    vanilla_model.HELD_ITEMS:setVisible(not hideVanilla)
    
    if not hideVanilla then
        models.model:setVisible(true)
        models.model:setParentType(nil)
        models.model:setPos(nil):setRot(nil)
        
        for name, part in pairs(LocalConfig.data.modelParts) do
            local def = LocalConfig.data.defaultTypes[name]
            part:setParentType(def or "None")
            part:setPos(nil):setRot(nil):setScale(nil)
        end
    else
        models.model:setParentType("World")
        for _, part in pairs(LocalConfig.data.modelParts) do
            part:setParentType("None")
        end
    end
end

--- Applies calculated values to a model part.
local function _apply(part, channel, val)
    if not part or not part.setPos then return end
    
    if channel == "position" then part:setPos(-val[1], val[2], val[3]) 
    elseif channel == "rotation" then part:setRot(-val[1], -val[2], -val[3])
    elseif channel == "scale" then part:setScale(val[1], val[2], val[3])
    end
end

--- Solves the math for a specific animation segment at a given progress (t).
local function _solveMath(seg, t)
    local v = {0,0,0}
    local type = seg.interp

    if type == INTERP.LINEAR then
        for i=1,3 do v[i] = seg.value[i] + seg.delta[i] * t end
        
    elseif type == INTERP.CATMULL then
        v[1] = Interpolation.catmullromEval(seg.coeffX, t)
        v[2] = Interpolation.catmullromEval(seg.coeffY, t)
        v[3] = Interpolation.catmullromEval(seg.coeffZ, t)
        
    elseif type == INTERP.BEZIER then
        local b, s, d = seg.bezier, seg.value, seg.delta
        for i=1,3 do
            v[i] = Interpolation.cubicBezier(t, s[i], s[i]+b.rightVal[i], (s[i]+d[i])+b.leftVal[i], s[i]+d[i])
        end
    end
    return v
end

--- Finds the active keyframe segment and applies it to the part.
local function _processChannel(part, channelName, segments, time)
    if #segments == 0 then return end

    local seg = segments[1]
    if time >= segments[#segments].time then
        seg = segments[#segments]
    else
        for i = #segments, 1, -1 do
            if time >= segments[i].time then seg = segments[i]; break end
        end
    end

    if time >= (seg.time + seg.duration) then
        local final = { seg.value[1]+seg.delta[1], seg.value[2]+seg.delta[2], seg.value[3]+seg.delta[3] }
        _apply(part, channelName, final)
        return
    end

    local t = math.clamp((time - seg.time) * seg.invDuration, 0, 1)
    local result = _solveMath(seg, t)
    _apply(part, channelName, result)
end

function AnimationPlayer.init(interp, conf, stream, utils)
    Interpolation, LocalConfig, StreamManager, RuzUtils = interp, conf, stream, utils
end

--- Starts a new animation state.
--- @param data table The animation data (chunks, duration, etc).
--- @param speed number Playback speed.
--- @param overrideVanilla boolean Hide vanilla model?
--- @param startTime number|nil Absolute world tick start time.
--- @param initiator string|nil The name of the initiator of the animation
--- @param onComplete function | nil a function to be played on completion
function AnimationPlayer.play(data, speed, overrideVanilla, startTime, initiator, onComplete)
    AnimationPlayer.stop()
    if not data then return end

    local initiatorPlayer = RuzUtils.findPlayer(initiator) or player
    ---@diagnostic disable-next-line
    RuzUtils.runAfterDelay(startTime-world:getTime(), function ()
        local pos = initiatorPlayer:getPos()
        local rot = initiatorPlayer:getBodyYaw()

        models.model:setParentType("World")
        models.model:setPos(pos*16)
        models.model:setRot(0, 180-rot, 0)

        if overrideVanilla then _setVanillaState(true) end
    end)

    AnimationPlayer.activeState = {
        transforms = data.transforms or {},
        duration = data.duration,
        overrideVanilla = overrideVanilla or false,
        startTime = startTime or world.getTime(),
        speed = tonumber(speed) or 1,
        events = data.events or {},
        eventsFired = {},
        onComplete = onComplete,

        hasReadHeader = false,
        readContext = nil 
    }
end

--- Stops the current animation and restores model state.
function AnimationPlayer.stop()
    if AnimationPlayer.activeState then
        StreamManager.stop()
        _setVanillaState(false)
        AnimationPlayer.activeState = nil
    end
end

--- Main render loop updater.
--- @param delta number Partial tick time.
function AnimationPlayer.update(delta)
    local state = AnimationPlayer.activeState
    if not state then return end

    --- @diagnostic disable-next-line
    local elapsed = (world:getTime() - state.startTime) + delta
    if elapsed < 0 then return end

    local time = math.min(elapsed * state.speed, state.duration)
    local isDone = time >= state.duration

    if state.events then
        for i, ev in ipairs(state.events) do
            if not state.eventsFired[i] and time >= ev.tick then
                state.eventsFired[i] = true
                if ev._fn then pcall(ev._fn) end
            end
        end
    end

    for partKey, channels in pairs(state.transforms) do
        local part = (type(partKey) == "string") and LocalConfig.data.modelParts[partKey] or partKey
        
        for chName, segments in pairs(channels) do
            _processChannel(part, chName, segments, time)
        end
    end

    if isDone then
        local cb = state.onComplete
        AnimationPlayer.stop()
        if cb then pcall(cb) end
    end
end

function pings.anim_header(start, override, speed, dur, initiator)
    AnimationPlayer.play({ duration = dur }, speed, override, start, initiator)
    
    AnimationPlayer.activeState.readContext = {
        lastPartId = -1, lastChId = -1, lastTime = 0, expectedVal = {0,0,0}, initiator = initiator
    }
end

function pings.anim_chunk(data)
    if AnimationPlayer.activeState then
        StreamManager.decodeChunkIntoState(data, AnimationPlayer.activeState)
    end
end

return AnimationPlayer